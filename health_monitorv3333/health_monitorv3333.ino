#include <Wire.h>
#include "MAX30105.h"
#include "MPU6050.h"
#include <math.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <time.h>
#include "AvgBucket.h"
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"

MAX30105 maxSensor;
MPU6050 mpu;
int16_t ax, ay, az, gx, gy, gz;

// ================= WIFI + FIREBASE =================
const char *WIFI_SSID = "KSIU-GUEST";
const char *WIFI_PASS = "ksiu12345";
const char *FIREBASE_RTDB_URL = "https://iot-health-monitoring-b51a7-default-rtdb.europe-west1.firebasedatabase.app";
const char *FIREBASE_PROJECT_ID = "iot-health-monitoring-b51a7";
const char *FIREBASE_API_KEY = "AIzaSyAAWOnV7BOH_lv3A4Uw-ZFtI5gPTtkwwF8";
const char *FIREBASE_USER_ID = "testUser";

const unsigned long LIVE_PUSH_MS = 1000;
const unsigned long AVG_30S_MS = 30000;
const unsigned long AVG_30M_MS = 1800000;

// ================= TEMP ================= (UNTOUCHED)
#define TEMP_PIN 34
float filteredTemp = 34.0;
#define RAW_SKIN 1800.0 // Calibrated: skin touch (~1800-1840)
#define RAW_AIR 2000.0  // Calibrated: room air (~1900+)
#define TEMP_SKIN 37.0
#define TEMP_AIR 25.0

float readTemp() {
  long sum = 0;
  for (int i = 0; i < 15; i++) {
    sum += analogRead(TEMP_PIN);
    delay(2);
  }
  float raw = sum / 15.0;
  static unsigned long lastTempPrint = 0;
  if (millis() - lastTempPrint > 1000) {
    lastTempPrint = millis();
    Serial.print("Raw Temp ADC: "); Serial.println(raw);
  }
  if (raw < RAW_SKIN) raw = RAW_SKIN;
  if (raw > RAW_AIR) raw = RAW_AIR;
  float temp = TEMP_SKIN + (raw - RAW_SKIN) * (TEMP_AIR - TEMP_SKIN) / (RAW_AIR - RAW_SKIN);
  filteredTemp = 0.9 * filteredTemp + 0.1 * temp;
  if (filteredTemp > 37.0) filteredTemp = 37.0;
  return filteredTemp;
}

// ================= MAX =================
const uint8_t MAX_SAMPLE_AVERAGE = 1;
const uint8_t MAX_LED_MODE = 2; // Standard Red + IR mode
const uint8_t MAX_SAMPLE_RATE = 50; // Lower rate to prevent FIFO overflow during WiFi
const uint16_t MAX_PULSE_WIDTH = 411;
const uint16_t MAX_ADC_RANGE = 16384;
const int MAX_BUF = 150; // Restored to 150 for stability and accuracy

uint32_t irBuf[MAX_BUF];
uint32_t redBuf[MAX_BUF];
int bufCount = 0;
float bpm = 0.0;
float spo2 = 0.0;
bool maxOk = false;
// FIX: red LED lower than IR so R ratio is correct for SpO2
uint8_t irLedCurrent = 0x3F; // Medium power start for better detection
uint8_t redLedCurrent = 0x3F; // Medium power start for better detection
bool fingerPresent = false;
unsigned long lastMaxCalcMs = 0;

// ================= FIREBASE RUNTIME =================
unsigned long lastLivePushMs = 0;
unsigned long last30sMs = 0;
unsigned long last30mMs = 0;
unsigned long lastManualSleepPollMs = 0;

float activityVariance = 0.0f;
int activityLevel = 0;  // 0 Stationary, 1 Low, 2 Moderate, 3 High
bool sleepMode = false;
bool manualSleepActive = false;
String currentDate = "";

AvgBucket bucket30s;
AvgBucket bucket30m;
AvgBucket bucketDay;
float dayMinBpm = 1000.0f, dayMaxBpm = -1.0f;
float dayMinSpo2 = 1000.0f, dayMaxSpo2 = -1.0f;
float dayMinTemp = 1000.0f, dayMaxTemp = -1.0f;

const int VAR_WIN = 20;
float magWindow[VAR_WIN];
int magIdx = 0;
int magCount = 0;

unsigned long nowEpochMs() {
  time_t nowTs = time(nullptr);
  if (nowTs > 1700000000) {
    return (unsigned long)(nowTs * 1000ULL);
  }
  return millis();
}

#define FINGER_ON 20000UL
#define FINGER_OFF 15000UL

float estimateBpmByPeaks(float *sm, int n, float fs, float ac) {
  float threshold = ac * 0.28f;
  int peaks[8];
  int peakCount = 0;
  int minGap = (int)(fs * 60.0f / 120.0f);
  if (minGap < 18) minGap = 18;
  int lastPeak = -minGap;

  for (int i = 2; i < n - 2; i++) {
    bool isPeak = sm[i] > threshold && sm[i] > sm[i - 1] && sm[i] >= sm[i + 1] && sm[i - 1] > sm[i - 2] && sm[i + 1] >= sm[i + 2];
    if (isPeak && i - lastPeak >= minGap) {
      if (peakCount < 8) peaks[peakCount++] = i;
      lastPeak = i;
    }
  }

  if (peakCount < 2) return 0;

  float gapSum = 0;
  int gapCount = 0;
  for (int i = 1; i < peakCount; i++) {
    int gap = peaks[i] - peaks[i - 1];
    if (gap >= (int)(fs * 60.0f / 160.0f) && gap <= (int)(fs * 60.0f / 45.0f)) {
      gapSum += gap;
      gapCount++;
    }
  }
  if (gapCount == 0) return 0;

  float bpmOut = 60.0f * fs / (gapSum / gapCount);
  if (bpmOut > 105.0f) {
    float half = bpmOut * 0.5f;
    if (half >= 45.0f) return half;
  }
  if (bpmOut < 45.0f || bpmOut > 160.0f) return 0;
  return bpmOut;
}

// ---------- BPM (Restored Version) ----------
float estimateBpm(uint32_t *ir, int n, float fs) {
  float mean = 0;
  for (int i = 0; i < n; i++) mean += ir[i];
  mean /= n;

  float s[MAX_BUF];
  for (int i = 0; i < n; i++) s[i] = (float)ir[i] - mean;

  // Simple Smoothing
  float sm[MAX_BUF];
  sm[0] = s[0];
  for (int i = 1; i < n - 1; i++) sm[i] = (s[i - 1] + s[i] + s[i + 1]) / 3.0f;
  sm[n - 1] = s[n - 1];

  float hi = sm[0], lo = sm[0];
  for (int i = 1; i < n; i++) {
    if (sm[i] > hi) hi = sm[i];
    if (sm[i] < lo) lo = sm[i];
  }
  float ac = hi - lo;
  if (ac < 25.0f) return 0; // Signal quality threshold

  float threshold = ac * 0.35f;
  int peaks[12];
  int peakCount = 0;
  int minGap = (int)(fs * 60.0f / 140.0f); // Max 140 BPM
  int lastPeak = -minGap;

  for (int i = 2; i < n - 2; i++) {
    if (sm[i] > threshold && sm[i] > sm[i - 1] && sm[i] >= sm[i + 1] && i - lastPeak >= minGap) {
      if (peakCount < 12) peaks[peakCount++] = i;
      lastPeak = i;
    }
  }

  if (peakCount < 2) return 0;

  float gapSum = 0;
  for (int i = 1; i < peakCount; i++) gapSum += (peaks[i] - peaks[i - 1]);
  float avgGap = gapSum / (peakCount - 1);
  float bpm = (60.0f * fs) / avgGap;

  if (bpm < 40 || bpm > 180) return 0;
  return bpm;
}

// ---------- SpO2 (Restored Version) ----------
float estimateSpo2(uint32_t *red, uint32_t *ir, int n) {
  float rDC = 0, iDC = 0;
  for (int i = 0; i < n; i++) {
    rDC += red[i];
    iDC += ir[i];
  }
  rDC /= n;
  iDC /= n;
  if (rDC < 1000 || iDC < 5000) return 0;

  float rMin = red[0], rMax = red[0], iMin = ir[0], iMax = ir[0];
  for (int i = 1; i < n; i++) {
    if (red[i] < rMin) rMin = red[i];
    if (red[i] > rMax) rMax = red[i];
    if (ir[i] < iMin) iMin = ir[i];
    if (ir[i] > iMax) iMax = ir[i];
  }
  float rAC = rMax - rMin;
  float iAC = iMax - iMin;
  if (rAC < 5 || iAC < 10) return 0; 

  float R = (rAC / rDC) / (iAC / iDC);
  if (R < 0.2f || R > 1.5f) return 0;

  float out = 106.0f - 12.0f * R;
  if (out > 100) out = 100;
  if (out < 88) out = 88;
  return out;
}

// ---------- LED auto-tune ----------
void autoTune() {
  float mean = 0;
  int sat = 0;
  for (int i = 0; i < MAX_BUF; i++) {
    mean += irBuf[i];
    if (irBuf[i] > 250000) sat++;
  }
  mean /= MAX_BUF;
  if (sat > 10) {
    if (irLedCurrent > 0x08) irLedCurrent -= 4;
    if (redLedCurrent > 0x08) redLedCurrent -= 2;  // red moves slower
  } else if (mean > 180000 && irLedCurrent > 0x08) {
    irLedCurrent -= 2;
  } else if (mean < 100000 && irLedCurrent < 0xFF) { 
    irLedCurrent = (irLedCurrent > 0xFB) ? 0xFF : irLedCurrent + 4;
    redLedCurrent = (redLedCurrent > 0xFD) ? 0xFF : redLedCurrent + 2;
  } else return;
  
  maxSensor.setPulseAmplitudeIR(irLedCurrent);
  maxSensor.setPulseAmplitudeRed(redLedCurrent);
  Serial.printf("AutoTune: IR=%d, RED=%d, Mean=%f\n", irLedCurrent, redLedCurrent, mean);
}

float correctRestingBpmHarmonic(float bpmVal) {
  if (activityLevel > 1) return bpmVal;
  if (bpmVal >= 108.0f && bpmVal <= 150.0f) {
    float half = bpmVal * 0.5f;
    if (half >= 54.0f && half <= 85.0f) return half;
  }
  return bpmVal;
}

void connectWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("WiFi connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");
}

void syncTime() {
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  time_t now = time(nullptr);
  int retries = 0;
  while (now < 1700000000 && retries < 25) {
    delay(300);
    now = time(nullptr);
    retries++;
  }
}

String getDateString(time_t ts) {
  struct tm tmData;
  gmtime_r(&ts, &tmData);
  char out[11];
  snprintf(out, sizeof(out), "%04d-%02d-%02d",
           tmData.tm_year + 1900, tmData.tm_mon + 1, tmData.tm_mday);
  return String(out);
}

void updateActivityState(int16_t x, int16_t y, int16_t z) {
  float mag = sqrtf((float)x * x + (float)y * y + (float)z * z);
  magWindow[magIdx] = mag;
  magIdx = (magIdx + 1) % VAR_WIN;
  if (magCount < VAR_WIN) magCount++;

  if (magCount < 5) return;

  float mean = 0.0f;
  for (int i = 0; i < magCount; i++) mean += magWindow[i];
  mean /= magCount;

  float var = 0.0f;
  for (int i = 0; i < magCount; i++) {
    float d = magWindow[i] - mean;
    var += d * d;
  }
  var /= magCount;
  activityVariance = var;

  if (var < 2000.0f) activityLevel = 0;
  else if (var < 80000.0f) activityLevel = 1;
  else if (var < 500000.0f) activityLevel = 2;
  else activityLevel = 3;

  bool autoSleep = (activityLevel == 0 && var < 500.0f);
  bool autoWake = (var > 80000.0f);
  if (manualSleepActive) {
    sleepMode = true;
  } else if (autoWake) {
    sleepMode = false;
  } else {
    sleepMode = autoSleep;
  }
}

String activityText() {
  if (activityLevel == 0) return "Stationary";
  if (activityLevel == 1) return "Low";
  if (activityLevel == 2) return "Moderate";
  return "High";
}

void addToBucket(AvgBucket &b, float bpmVal, float spo2Val, float tempVal, long irVal, float varVal, int activityVal) {
  b.bpmSum += bpmVal;
  b.spo2Sum += spo2Val;
  b.tempSum += tempVal;
  b.irSum += irVal;
  b.varSum += varVal;
  b.activitySum += activityVal;
  b.count++;
}

void pushToRealtime(long irValue, float bpmVal, float spo2Val, float tempVal) {
  if (WiFi.status() != WL_CONNECTED) return;

  String url = String(FIREBASE_RTDB_URL) + "/live/" + FIREBASE_USER_ID + ".json";
  float tempDetected = (tempVal > 30.0f) ? 1.0f : 0.0f;
  String payload = "{";
  payload += "\"ir\":" + String(irValue) + ",";
  payload += "\"bpm\":" + String(bpmVal, 2) + ",";
  payload += "\"spo2\":" + String(spo2Val, 2) + ",";
  payload += "\"temp\":" + String(tempVal, 2) + ",";
  payload += "\"tempdet\":" + String(tempDetected, 1) + ",";
  payload += "\"activity\":\"" + activityText() + "\",";
  payload += "\"skin\":" + String(fingerPresent ? "true" : "false") + ",";
  payload += "\"manualSleepActive\":" + String(manualSleepActive ? "true" : "false") + ",";
  payload += "\"sleepMode\":" + String(sleepMode ? "true" : "false") + ",";
  payload += "\"ts\":" + String(nowEpochMs());
  payload += "}";

  HTTPClient http;
  http.begin(url);
  http.setTimeout(700);
  http.addHeader("Content-Type", "application/json");
  int code = http.PATCH(payload);
  Serial.print("RTDB code: ");
  Serial.println(code);
  http.end();
}

void pollManualSleepFlag() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (millis() - lastManualSleepPollMs < 5000) return;
  lastManualSleepPollMs = millis();

  String url = String(FIREBASE_RTDB_URL) + "/live/" + FIREBASE_USER_ID + "/manualSleepActive.json";
  HTTPClient http;
  http.begin(url);
  http.setTimeout(700);
  int code = http.GET();
  if (code > 0) {
    String body = http.getString();
    body.trim();
    if (body == "true") manualSleepActive = true;
    else if (body == "false" || body == "null") manualSleepActive = false;
  }
  http.end();
}

// ---------- main sensor process ----------
void processMax() {
  if (!maxOk) return;
  maxSensor.check(); // MUST be called to poll the sensor
  
  static unsigned long lastCheck = 0;
  bool avail = maxSensor.available();
  if (millis() - lastCheck > 2000) {
    lastCheck = millis();
    Serial.printf("Sensor OK: %d, Data Available: %u, Finger: %d\n", maxOk, (unsigned int)avail, fingerPresent);
  }

  while (maxSensor.available()) {
    static bool firstSample = true;
    if (firstSample) { Serial.println(">>> DATA RECEIVED! SENSOR IS WORKING <<<"); firstSample = false; }
    uint32_t ir = maxSensor.getIR();
    uint32_t red = maxSensor.getRed();
    maxSensor.nextSample();

    if (ir > FINGER_ON && !fingerPresent) {
      fingerPresent = true;
      bufCount = 0;
      Serial.println("Finger ON");
    }

    if (ir < FINGER_OFF && fingerPresent) {
      fingerPresent = false;
      bufCount = 0;
      bpm = 0;
      spo2 = 0;
      Serial.println("Finger OFF");
    }

    // DIAGNOSTIC: Print raw values even when no finger is present
    static unsigned long lastDiag = 0;
    if (millis() - lastDiag > 500) {
      lastDiag = millis();
      Serial.print(">>> RAW SENSOR DATA - IR: "); Serial.print(ir);
      Serial.print(" | RED: "); Serial.print(red);
      Serial.print(" | Finger: "); Serial.println(fingerPresent ? "YES" : "NO");
    }

    if (!fingerPresent) continue;

    if (bufCount < MAX_BUF) {
      irBuf[bufCount] = ir;
      redBuf[bufCount] = red;
      bufCount++;
      if (bufCount == MAX_BUF) Serial.println("Buffer full, computing...");
    } else {
      memmove(irBuf, irBuf + 1, (MAX_BUF - 1) * sizeof(uint32_t));
      memmove(redBuf, redBuf + 1, (MAX_BUF - 1) * sizeof(uint32_t));
      irBuf[MAX_BUF - 1] = ir;
      redBuf[MAX_BUF - 1] = red;
    }
  }

  if (bufCount < MAX_BUF) return;
  if (millis() - lastMaxCalcMs < 700) return;  // stable update period
  lastMaxCalcMs = millis();

  autoTune();
  float nb = estimateBpm(irBuf, MAX_BUF, (float)MAX_SAMPLE_RATE);
  nb = correctRestingBpmHarmonic(nb);
  float ns = estimateSpo2(redBuf, irBuf, MAX_BUF);

  if (nb > 0) {
    if (bpm == 0) {
      bpm = nb;
    } else {
      float delta = nb - bpm;
      if (delta > 4.0f) delta = 4.0f;
      if (delta < -4.0f) delta = -4.0f;
      bpm += delta;
    }
    
  }
  if (ns > 0) {
    if (spo2 == 0) {
      spo2 = ns;
    } else {
      float deltaS = ns - spo2;
      if (deltaS > 0.6f) deltaS = 0.6f;
      if (deltaS < -0.6f) deltaS = -0.6f;
      spo2 += deltaS;
    }
  }
}

// ================= SETUP =================
void writeRegister8(uint8_t adr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(adr);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);  // Disable brownout detector for stable battery operation
  Serial.begin(115200);
  delay(2000);
  Wire.begin(21, 22);
  Wire.setClock(100000); // Stable I2C speed for jumper wires

  Serial.println("Scanning I2C bus...");
  for (byte address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      Serial.print("Found I2C device at 0x");
      if (address < 16) Serial.print("0");
      Serial.println(address, HEX);
    }
  }

  connectWiFi();
  syncTime();
  time_t nowTs = time(nullptr);
  currentDate = (nowTs > 1700000000) ? getDateString(nowTs) : "1970-01-01";

  Serial.println("--- MAX30102 DIAGNOSTIC START ---");
  if (maxSensor.begin(Wire)) {
    Serial.println("STEP 1: I2C Communication OK");
    maxSensor.softReset();
    delay(500); // Longer delay for reset
    
    // Explicitly set each parameter
    maxSensor.setLEDMode(2); // Red + IR
    maxSensor.setPulseWidth(411);
    maxSensor.setSampleRate(100);
    maxSensor.setADCRange(16384);
    
    // Force maximum visibility
    maxSensor.setPulseAmplitudeRed(0xFF); 
    maxSensor.setPulseAmplitudeIR(0xFF);
    irLedCurrent = 0xFF;
    redLedCurrent = 0xFF;
    
    maxOk = true;
    Serial.println("STEP 2: Setup Commands Sent");
    Serial.print("Part ID: 0x"); Serial.println(maxSensor.readPartID(), HEX);
    Serial.println("--- MAX30102 INITIALIZED OK ---");
  } else {
    Serial.println("!!! MAX30102 NOT FOUND !!!");
    Serial.println("Please check:");
    Serial.println("1. SDA connected to Pin 21");
    Serial.println("2. SCL connected to Pin 22");
    Serial.println("3. Power (3.3V) and Ground");
    maxOk = false;
  }

  // MPU6050 (UNTOUCHED)
  mpu.initialize();
  Serial.println(mpu.testConnection() ? "MPU6050 OK" : "MPU6050 FAIL");

  // ADC (UNTOUCHED)
  analogReadResolution(12);
  analogSetPinAttenuation(TEMP_PIN, ADC_11db);
}

// ================= LOOP =================
void loop() {
  processMax();
  pollManualSleepFlag();

  static unsigned long lastPrint = 0;
  if (millis() - lastPrint >= 100) {
    lastPrint = millis();

    long irValue = (maxOk && bufCount > 0) ? (long)irBuf[bufCount - 1] : 0;

    // MPU6050 (UNTOUCHED)
    mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);
    updateActivityState(ax, ay, az);

    // TEMP (UNTOUCHED)
    float temp = readTemp();

    bool validVitals = fingerPresent && bpm > 0.0f && spo2 > 0.0f && temp > 20.0f && temp < 45.0f;
    if (validVitals) {
      addToBucket(bucket30s, bpm, spo2, temp, irValue, activityVariance, activityLevel);
    }

    if (millis() - lastLivePushMs >= LIVE_PUSH_MS) {
      lastLivePushMs = millis();
      pushToRealtime(irValue, bpm, spo2, temp);
    }

    if (millis() - last30sMs >= AVG_30S_MS) {
      last30sMs = millis();
      if (bucket30s.count > 0) {
        // Aggregation is now handled by Python service via RTDB 'live' node.
        bucket30s = AvgBucket();
      }
    }

    if (millis() - last30mMs >= AVG_30M_MS) {
      last30mMs = millis();
      if (bucket30m.count > 0) {
        bucket30m = AvgBucket();
      }
    }

    time_t nowTs = time(nullptr);
    String nowDate = (nowTs > 1700000000) ? getDateString(nowTs) : currentDate;
    if (nowDate != currentDate) {
      bucketDay = AvgBucket();
      dayMinBpm = 1000.0f;
      dayMaxBpm = -1.0f;
      dayMinSpo2 = 1000.0f;
      dayMaxSpo2 = -1.0f;
      dayMinTemp = 1000.0f;
      dayMaxTemp = -1.0f;
      currentDate = nowDate;
    }

    Serial.print("IR: ");
    Serial.print(irValue);
    Serial.print(" | BPM: ");
    Serial.print(bpm, 1);
    Serial.print(" | SpO2: ");
    Serial.print(spo2, 1);
    Serial.print(" | Finger: ");
    Serial.print(fingerPresent ? "YES" : "NO");
    Serial.print(" | AX: ");
    Serial.print(ax);
    Serial.print(" AY: ");
    Serial.print(ay);
    Serial.print(" AZ: ");
    Serial.print(az);
    Serial.print(" | Temp: ");
    Serial.print(temp);
    Serial.print(" | Act: ");
    Serial.print(activityText());
    Serial.print(" | Sleep: ");
    Serial.print(sleepMode ? "1" : "0");
    Serial.println(" C");
  }
}
