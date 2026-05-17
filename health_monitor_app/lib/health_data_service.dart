import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class HealthReading {
  final double bpm;
  final double spo2;
  final double temp;
  final double tempdet;
  final int ir;
  final String activity;
  final bool skin;
  final bool sleepMode;
  final bool manualSleepActive;
  final bool standbyMode;
  final int timestamp;
  final DateTime dateTime;

  HealthReading({
    required this.bpm,
    required this.spo2,
    required this.temp,
    required this.tempdet,
    required this.ir,
    required this.activity,
    required this.skin,
    required this.sleepMode,
    required this.manualSleepActive,
    required this.standbyMode,
    required this.timestamp,
  }) : dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);

  factory HealthReading.fromMap(Map<dynamic, dynamic> map) {
    final tsRaw =
        map['timestamp'] ?? map['ts'] ?? map['time'] ?? map['timestamp_ms'];
    final tsNum = tsRaw is num ? tsRaw : 0;
    int ts = tsNum.toInt();
    if (ts < 1000000000000) ts *= 1000;

    final activity =
        (map['activity'] ?? map['act'])?.toString() ?? 'Stationary';

    return HealthReading(
      bpm: (map['bpm'] as num?)?.toDouble() ?? 0,
      spo2: (map['spo2'] as num?)?.toDouble() ?? 0,
      temp: (map['temp'] as num?)?.toDouble() ?? 0,
      tempdet: (map['tempdet'] as num?)?.toDouble() ?? 0,
      ir: (map['ir'] as num?)?.toInt() ?? 0,
      activity: activity,
      skin: (map['skin'] as bool?) ?? (map['skinOn'] as bool?) ?? false,
      sleepMode: (map['sleepMode'] as bool?) ?? false,
      manualSleepActive: (map['manualSleepActive'] as bool?) ?? false,
      standbyMode: (map['standbyMode'] as bool?) ?? false,
      timestamp: ts.toInt(),
    );
  }
}

/// 1-minute trend entry — read from aggregates/{uid}/{date}/{bucket}
class TrendEntry {
  final DateTime dateTime;
  final double bpm;
  final double spo2;
  final double temp;
  final double variance;
  final int activity;

  const TrendEntry({
    required this.dateTime,
    required this.bpm,
    required this.spo2,
    required this.temp,
    required this.variance,
    required this.activity,
  });

  factory TrendEntry.fromMap(Map<dynamic, dynamic> map, String bucketKey) {
    // bucketKey is HHmmss, e.g. "143000" => 14:30:00
    final h = int.tryParse(bucketKey.substring(0, 2)) ?? 0;
    final m = int.tryParse(bucketKey.substring(2, 4)) ?? 0;
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, h, m);

    return TrendEntry(
      dateTime: dt,
      bpm: (map['bpm'] as num?)?.toDouble() ?? 0,
      spo2: (map['spo2'] as num?)?.toDouble() ?? 0,
      temp: (map['temp'] as num?)?.toDouble() ?? 0,
      variance: 0,
      activity: (map['activity'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Insight entry — read from insights/{uid}/{date}/{pushId}
class InsightItem {
  final String type;
  final String sensor;
  final String message;
  final String severity;
  final DateTime timestamp;

  const InsightItem({
    required this.type,
    required this.sensor,
    required this.message,
    required this.severity,
    required this.timestamp,
  });

  factory InsightItem.fromMap(Map<dynamic, dynamic> map) {
    final tsMs = (map['timestamp'] as num?)?.toInt() ?? 0;
    return InsightItem(
      type: map['type']?.toString() ?? '',
      sensor: map['sensor']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      severity: map['severity']?.toString() ?? 'info',
      timestamp: tsMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(tsMs)
          : DateTime.now(),
    );
  }
}

/// Day summary computed on the fly from aggregates in RTDB.
class DaySummary {
  final double avgBpm;
  final double avgSpo2;
  final double avgTemp;
  final double minBpm;
  final double maxBpm;
  final double minSpo2;
  final double maxSpo2;
  final double minTemp;
  final double maxTemp;

  const DaySummary({
    required this.avgBpm,
    required this.avgSpo2,
    required this.avgTemp,
    required this.minBpm,
    required this.maxBpm,
    required this.minSpo2,
    required this.maxSpo2,
    required this.minTemp,
    required this.maxTemp,
  });
}

enum HealthStatus { normal, warning, critical }

class HealthDataService {
  final DatabaseReference _rootRef = FirebaseDatabase.instance.ref();

  // ── Live reading ──────────────────────────────────────────────────────────

  /// Path: live/{uid}
  Stream<HealthReading?> getLatestReadingStream(String uid) {
    return _rootRef.child('live').child(uid).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      if (data is Map) return HealthReading.fromMap(data as Map<dynamic, dynamic>);
      return null;
    });
  }

  Future<void> setManualSleepActive(String uid, bool value) async {
    await _rootRef.child('live').child(uid).child('manualSleepActive').set(value);
  }

  // ── 1-min history/trends ──────────────────────────────────────────────────
  
  /// Path: aggregates/{uid}/{date}
  /// Returns a live stream that re-fires whenever any bucket changes.
  Stream<List<TrendEntry>> getTrendHistory(String uid, String date) {
    return _rootRef
        .child('aggregates')
        .child(uid)
        .child(date)
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return const <TrendEntry>[];
      final map = data as Map<dynamic, dynamic>;
      final entries = map.entries
          .where((e) => e.value is Map)
          .map((e) => TrendEntry.fromMap(
                e.value as Map<dynamic, dynamic>,
                e.key.toString(),
              ))
          .toList();
      entries.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      return entries;
    });
  }

  // ── Insights ──────────────────────────────────────────────────────────────

  /// Path: insights/{uid}/{date}  (latest date = today)
  Stream<List<InsightItem>> getInsights(String uid) {
    final date = _dateKey(DateTime.now());
    return _rootRef
        .child('insights')
        .child(uid)
        .child(date)
        .onValue
        .map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return const <InsightItem>[];
      final map = data as Map<dynamic, dynamic>;
      final items = map.values
          .whereType<Map>()
          .map((v) => InsightItem.fromMap(v as Map<dynamic, dynamic>))
          .toList();
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    });
  }

  // ── Day summary ───────────────────────────────────────────────────────────

  /// Computed from aggregates/{uid}/{date}
  Stream<DaySummary?> getDaySummary(String uid, String date) {
    return getTrendHistory(uid, date).map((entries) {
      if (entries.isEmpty) return null;
      final bpms = entries.map((e) => e.bpm).where((v) => v > 0).toList();
      final spo2s = entries.map((e) => e.spo2).where((v) => v > 0).toList();
      final temps = entries.map((e) => e.temp).where((v) => v > 0).toList();

      double avg(List<double> l) =>
          l.isEmpty ? 0 : l.reduce((a, b) => a + b) / l.length;

      return DaySummary(
        avgBpm: avg(bpms),
        avgSpo2: avg(spo2s),
        avgTemp: avg(temps),
        minBpm: bpms.isEmpty ? 0 : bpms.reduce((a, b) => a < b ? a : b),
        maxBpm: bpms.isEmpty ? 0 : bpms.reduce((a, b) => a > b ? a : b),
        minSpo2: spo2s.isEmpty ? 0 : spo2s.reduce((a, b) => a < b ? a : b),
        maxSpo2: spo2s.isEmpty ? 0 : spo2s.reduce((a, b) => a > b ? a : b),
        minTemp: temps.isEmpty ? 0 : temps.reduce((a, b) => a < b ? a : b),
        maxTemp: temps.isEmpty ? 0 : temps.reduce((a, b) => a > b ? a : b),
      );
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static HealthStatus getHeartRateStatus(double heartRate) {
    if (heartRate >= 60 && heartRate <= 100) return HealthStatus.normal;
    if ((heartRate >= 50 && heartRate < 60) ||
        (heartRate > 100 && heartRate <= 120)) {
      return HealthStatus.warning;
    }
    return HealthStatus.critical;
  }

  static HealthStatus getSpO2Status(double spo2) {
    if (spo2 >= 95 && spo2 <= 100) return HealthStatus.normal;
    if (spo2 >= 92 && spo2 < 95) return HealthStatus.warning;
    return HealthStatus.critical;
  }

  static HealthStatus getOverallStatus(double heartRate, double spo2) {
    final hr = getHeartRateStatus(heartRate);
    final ox = getSpO2Status(spo2);
    if (hr == HealthStatus.critical || ox == HealthStatus.critical) {
      return HealthStatus.critical;
    }
    if (hr == HealthStatus.warning || ox == HealthStatus.warning) {
      return HealthStatus.warning;
    }
    return HealthStatus.normal;
  }

  static Color getStatusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.normal:
        return Colors.green;
      case HealthStatus.warning:
        return Colors.orange;
      case HealthStatus.critical:
        return Colors.red;
    }
  }

  static String getStatusText(HealthStatus status) {
    switch (status) {
      case HealthStatus.normal:
        return 'Normal';
      case HealthStatus.warning:
        return 'Warning';
      case HealthStatus.critical:
        return 'Critical';
    }
  }

  static Color insightColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'danger':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'caution':
        return Colors.amber;
      default:
        return Colors.blue;
    }
  }
}
