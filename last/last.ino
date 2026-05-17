#include <WiFi.h>
#include <HTTPClient.h>
#include <Wire.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"

/* ===== TEMPERATURE ===== */
#include <OneWire.h>
#include <DallasTemperature.h>

#define ONE_WIRE_BUS 4   // DS18B20 DATA على GPIO4
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature tempSensor(&oneWire);

float bodyTemp = 0;


/* ===== MAX SENSOR ===== */
MAX30105 particleSensor;

/* WiFi */
const char* ssid = "KSIU-GUEST";
const char* password = "ksiu123";

/* ===== FIREBASE CONFIG ===== */
const char* firebaseURL =
"https://iot-health-monitoring-b51a7-default-rtdb.europe-west1.firebasedatabase.app/users/testUser/health.json";

/* ===== SENSOR BUFFERS ===== */
#define BUFFER_SIZE 100
uint32_t irBuffer[BUFFER_SIZE];
uint32_t redBuffer[BUFFER_SIZE];

int32_t spo2;
int8_t validSpO2;
int32_t heartRate;
int8_t validHeartRate;

void setup() {
  Serial.begin(115200);
  Wire.begin();

  /* ===== INIT TEMP SENSOR ===== */
  tempSensor.begin();

  /* ===== CONNECT WIFI ===== */
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected");
  Serial.println(WiFi.localIP());

  /* ===== INIT MAX30102 ===== */
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 not found. Check wiring.");
    while (1);
  }

  particleSensor.setup(
    60,
    4,
    2,
    100,
    411,
    4096
  );

  Serial.println("Place finger on sensor");
}

void loop() {

  /* ===== READ MAX30102 ===== */
  for (int i = 0; i < BUFFER_SIZE; i++) {
    while (!particleSensor.available()) {
      particleSensor.check();
    }

    redBuffer[i] = particleSensor.getRed();
    irBuffer[i]  = particleSensor.getIR();
    particleSensor.nextSample();
  }

  maxim_heart_rate_and_oxygen_saturation(
    irBuffer,
    BUFFER_SIZE,
    redBuffer,
    &spo2,
    &validSpO2,
    &heartRate,
    &validHeartRate
  );

  /* ===== READ TEMPERATURE ===== */
  tempSensor.requestTemperatures();
  bodyTemp = tempSensor.getTempCByIndex(0);

  Serial.print("Temp: ");
  Serial.println(bodyTemp);

  /* ===== VALIDATION + SEND ===== */
  if (validHeartRate && validSpO2 &&
      heartRate > 40 && heartRate < 180 &&
      spo2 > 85 && spo2 <= 100 &&
      bodyTemp > 20 && bodyTemp < 45) {

    sendToFirebase(heartRate, spo2, bodyTemp);

    Serial.print("HR: ");
    Serial.print(heartRate);
    Serial.print(" | SpO2: ");
    Serial.print(spo2);
    Serial.print(" | Temp: ");
    Serial.println(bodyTemp);

  } else {
    Serial.println("Invalid reading, retrying...");
  }

  delay(3000);
}

/* ===== SEND DATA TO FIREBASE ===== */
void sendToFirebase(int hr, int sp, float temp) {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(firebaseURL);
    http.addHeader("Content-Type", "application/json");

    String payload = "{";
    payload += "\"heartRate\":" + String(hr) + ",";
    payload += "\"spo2\":" + String(sp) + ",";
    payload += "\"temperature\":" + String(temp) + ",";
    payload += "\"timestamp\":" + String(millis());
    payload += "}";

    int httpResponseCode = http.PUT(payload);

    Serial.print("Firebase response: ");
    Serial.println(httpResponseCode);

    http.end();
  } else {
    Serial.println("WiFi disconnected");
  }
}