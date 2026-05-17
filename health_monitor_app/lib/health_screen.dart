import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'health_data_service.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  final _healthDataService = HealthDataService();
  static const String _deviceDataUserId = 'testUser';
  final List<_LocalAlert> _alerts = [];
  int _bottomIndex = 0;
  DateTime? _dangerStartedAt;
  bool _dangerAlertSent = false;

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final date = _dateKey(DateTime.now());

    return DefaultTabController(
      length: 5,
      child: StreamBuilder<HealthReading?>(
        stream: _healthDataService.getLatestReadingStream(_deviceDataUserId),
        builder: (context, liveSnapshot) {
          final reading = liveSnapshot.data;
          _trackDangerAlert(reading);
          return Scaffold(
            backgroundColor: const Color(0xFFF8F3FF),
            bottomNavigationBar: _buildBottomNav(),
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFEAF0FF),
                    Color(0xFFFFF3F8),
                    Color(0xFFF9F4FF),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        children: [
                          _buildHeader(user.email, authService),
                          if (_bottomIndex == 0) ...[
                            const SizedBox(height: 18),
                            _buildOverallCard(reading),
                            const SizedBox(height: 14),
                            _buildTabs(),
                          ] else ...[
                            const SizedBox(height: 18),
                            _buildPageTitle(),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      child: _buildBottomPage(reading, date, user.email, authService),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(String? email, AuthService authService) {
    final initial = (email?.isNotEmpty ?? false) ? email![0].toUpperCase() : 'R';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF12214A),
                  ),
                  children: [
                    TextSpan(text: 'Health '),
                    TextSpan(
                      text: 'Monitor',
                      style: TextStyle(color: Color(0xFF5A45FF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Track your vitals. Stay healthy.',
                style: TextStyle(
                  color: Color(0xFF7D88A8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'logout') await authService.logout();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Logout'),
                ],
              ),
            ),
          ],
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF604DFF),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: 2,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14C88B),
                    border: Border.all(color: Colors.white, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverallCard(HealthReading? reading) {
    final status = HealthDataService.getOverallStatus(
      reading?.bpm ?? 0,
      reading?.spo2 ?? 0,
    );
    final healthy = reading != null && status == HealthStatus.normal;
    final label = healthy ? 'Good' : HealthDataService.getStatusText(status);
    final color = healthy ? const Color(0xFF18B66A) : HealthDataService.getStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCardDecoration(),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF42C6FF), Color(0xFF7557FF)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x554F64FF),
                  blurRadius: 18,
                  offset: Offset(0, 9),
                ),
              ],
            ),
            child: const Icon(Icons.show_chart, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overall Status',
                  style: TextStyle(
                    color: Color(0xFF607093),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'All vitals are within safe range.',
                  style: TextStyle(
                    color: Color(0xFF7D88A8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE8F1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x55FF4D79),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.favorite, color: Color(0xFFFF315F), size: 58),
                const Icon(Icons.monitor_heart, color: Colors.white, size: 42),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: TabBar(
        isScrollable: true,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF647090),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A5CFF), Color(0xFF8B5CFF)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x556A5CFF),
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
        ),
        tabs: const [
          Tab(child: _TabLabel(icon: Icons.monitor_heart, label: 'Live')),
          Tab(child: _TabLabel(icon: Icons.nightlight_round, label: 'Sleep')),
          Tab(child: _TabLabel(icon: Icons.tips_and_updates_outlined, label: 'Insights')),
          Tab(child: _TabLabel(icon: Icons.calendar_month_outlined, label: 'History')),
          Tab(child: _TabLabel(icon: Icons.event_note_outlined, label: 'Summary')),
        ],
      ),
    );
  }

  Widget _buildPageTitle() {
    final data = switch (_bottomIndex) {
      1 => (Icons.bar_chart_rounded, 'Trends', 'Review recent 1-minute trend data.'),
      2 => (Icons.notifications_active_outlined, 'Alerts', 'Critical states that lasted long enough to warn.'),
      3 => (Icons.person_outline_rounded, 'Profile', 'Account and device status.'),
      _ => (Icons.home_rounded, 'Home', 'Live monitoring dashboard.'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _softCardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF6A5CFF).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(data.$1, color: const Color(0xFF6A5CFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.$2,
                  style: const TextStyle(
                    color: Color(0xFF12214A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.$3,
                  style: const TextStyle(
                    color: Color(0xFF7D88A8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPage(
    HealthReading? reading,
    String date,
    String? email,
    AuthService authService,
  ) {
    if (_bottomIndex == 1) return _buildTrendsPage(_deviceDataUserId, date);
    if (_bottomIndex == 2) return _buildAlertsPage(reading);
    if (_bottomIndex == 3) return _buildProfilePage(email, authService, reading);
    return TabBarView(
      children: [
        _buildLiveTab(reading),
        _buildSleepTab(_deviceDataUserId, reading),
        _buildInsightsTab(_deviceDataUserId),
        _buildHistoryTab(_deviceDataUserId, date),
        _buildSummaryTab(_deviceDataUserId, date),
      ],
    );
  }

  Widget _buildLiveTab(HealthReading? reading) {
    final hasData = reading != null && reading.bpm > 0 && reading.spo2 > 0;
    final heartRate = reading?.bpm ?? 0;
    final spo2 = reading?.spo2 ?? 0;
    final temp = reading?.temp ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      children: [
        _buildConnectionCard(reading, hasData),
        const SizedBox(height: 16),
        _MetricCard(
          title: 'Heart Rate',
          value: heartRate > 0 ? heartRate.toStringAsFixed(1) : '--',
          unit: 'BPM',
          normalText: 'Normal: 60-100 BPM',
          rangeText: 'Range: 40-180 BPM',
          icon: Icons.favorite,
          color: const Color(0xFFFF315F),
          statusText: _metricBadgeText(HealthDataService.getHeartRateStatus(heartRate), 'Elevated'),
          progress: ((heartRate - 40) / 140).clamp(0.0, 1.0).toDouble(),
          ringValue: ((heartRate - 40) / 140).clamp(0.0, 1.0).toDouble(),
          sparkline: const [0.25, 0.32, 0.29, 0.38, 0.34, 0.48, 0.41, 0.58, 0.43, 0.62, 0.76, 0.55, 0.48, 0.52],
          hot: true,
        ),
        const SizedBox(height: 16),
        _MetricCard(
          title: 'SpO2',
          value: spo2 > 0 ? spo2.toStringAsFixed(1) : '--',
          unit: '%',
          normalText: 'Normal: 95-100%',
          rangeText: 'Range: 80-100%',
          icon: Icons.air,
          color: const Color(0xFF18BFA6),
          statusText: HealthDataService.getStatusText(HealthDataService.getSpO2Status(spo2)),
          progress: ((spo2 - 80) / 20).clamp(0.0, 1.0).toDouble(),
          ringValue: (spo2 / 100).clamp(0.0, 1.0).toDouble(),
          sparkline: const [0.50, 0.52, 0.51, 0.54, 0.55, 0.56, 0.54, 0.58, 0.57, 0.60, 0.59, 0.61, 0.60, 0.62],
        ),
        const SizedBox(height: 16),
        _MetricCard(
          title: 'Temperature',
          value: temp > 0 ? temp.toStringAsFixed(1) : '--',
          unit: 'C',
          normalText: 'Normal: 36.1-37.2 C',
          rangeText: 'Range: 35.0-38.0 C',
          icon: Icons.thermostat,
          color: const Color(0xFFFF7A1A),
          statusText: HealthDataService.getStatusText(_tempStatus(temp)),
          progress: ((temp - 35) / 3).clamp(0.0, 1.0).toDouble(),
          ringValue: ((temp - 35) / 3).clamp(0.0, 1.0).toDouble(),
          sparkline: const [0.45, 0.45, 0.46, 0.46, 0.47, 0.46, 0.47, 0.48, 0.48, 0.49, 0.49, 0.48, 0.49, 0.50],
          warm: true,
        ),
        const SizedBox(height: 16),
        _buildActivityCard(reading?.activity ?? 'Unknown'),
      ],
    );
  }

  Widget _buildConnectionCard(HealthReading? reading, bool hasData) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _softCardDecoration(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE0FFF1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              hasData ? Icons.sensors : Icons.sensors_off,
              color: hasData ? const Color(0xFF12B76A) : const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasData ? 'Live stream connected' : 'Waiting for ESP32 live data',
                  style: const TextStyle(
                    color: Color(0xFF1F2A44),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reading == null
                      ? 'Path: live/testUser'
                      : 'Activity: ${reading.activity}    Skin: ${reading.skin ? "ON" : "OFF"}',
                  style: const TextStyle(
                    color: Color(0xFF7D88A8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            hasData ? Icons.check_circle : Icons.warning_rounded,
            color: hasData ? const Color(0xFF16B364) : const Color(0xFFF59E0B),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepTab(String uid, HealthReading? reading) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Manual Sleep Mode', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Writes manualSleepActive to Realtime DB'),
            value: reading?.manualSleepActive ?? false,
            onChanged: (v) => _healthDataService.setManualSleepActive(uid, v),
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: Text(
            reading == null
                ? 'No live data yet.'
                : 'Sleep mode: ${reading.sleepMode ? "ACTIVE" : "OFF"}\n'
                    'BPM: ${reading.bpm.toStringAsFixed(1)}\n'
                    'SpO2: ${reading.spo2.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildInsightsTab(String uid) {
    return StreamBuilder<List<InsightItem>>(
      stream: _healthDataService.getInsights(uid),
      builder: (context, snapshot) {
        final insights = snapshot.data ?? const <InsightItem>[];
        if (insights.isEmpty) return _emptyState('No insights yet.');
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: insights.length,
          itemBuilder: (context, i) {
            final item = insights[i];
            final color = HealthDataService.insightColor(item.severity);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _sectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.16),
                    child: Icon(Icons.tips_and_updates_outlined, color: color),
                  ),
                  title: Text(item.message, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${item.severity.toUpperCase()}  ${item.sensor}  ${_formatDateTime(item.timestamp)}'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTab(String uid, String date) {
    return StreamBuilder<List<TrendEntry>>(
      stream: _healthDataService.getTrendHistory(uid, date),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <TrendEntry>[];
        if (rows.isEmpty) return _emptyState('No 1-min history for $date');
        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final e = rows[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _sectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${_formatDateTime(e.dateTime)}  BPM ${e.bpm.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'SpO2 ${e.spo2.toStringAsFixed(1)}%  Temp ${e.temp.toStringAsFixed(1)}C  Activity ${e.activity}',
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryTab(String uid, String date) {
    return StreamBuilder<DaySummary?>(
      stream: _healthDataService.getDaySummary(uid, date),
      builder: (context, snapshot) {
        final s = snapshot.data;
        if (s == null) return _emptyState('No day summary for $date');
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _summaryTile('Average BPM', s.avgBpm),
            _summaryTile('Average SpO2', s.avgSpo2, suffix: '%'),
            _summaryTile('Average Temp', s.avgTemp, suffix: 'C'),
            _summaryTile('Min/Max BPM', s.minBpm, secondary: s.maxBpm),
            _summaryTile('Min/Max SpO2', s.minSpo2, secondary: s.maxSpo2, suffix: '%'),
            _summaryTile('Min/Max Temp', s.minTemp, secondary: s.maxTemp, suffix: 'C'),
          ],
        );
      },
    );
  }

  Widget _buildTrendsPage(String uid, String date) {
    return StreamBuilder<List<TrendEntry>>(
      stream: _healthDataService.getTrendHistory(uid, date),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <TrendEntry>[];
        if (rows.isEmpty) return _emptyState('No trend data yet. Wait for 1-min buckets.');
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _trendCard(
              'Heart Rate',
              'BPM',
              const Color(0xFFFF315F),
              rows.map((e) => e.bpm).toList(),
              Icons.favorite,
            ),
            const SizedBox(height: 14),
            _trendCard(
              'SpO2',
              '%',
              const Color(0xFF18BFA6),
              rows.map((e) => e.spo2).toList(),
              Icons.air,
            ),
            const SizedBox(height: 14),
            _trendCard(
              'Temperature',
              'C',
              const Color(0xFFFF7A1A),
              rows.map((e) => e.temp).toList(),
              Icons.thermostat,
            ),
            const SizedBox(height: 14),
            _trendCard(
              'Activity',
              'level',
              const Color(0xFF6A5CFF),
              rows.map((e) => e.activity.toDouble()).toList(),
              Icons.directions_run,
            ),
          ],
        );
      },
    );
  }

  Widget _trendCard(String title, String unit, Color color, List<double> values, IconData icon) {
    final clean = values.where((v) => v > 0).toList();
    final latest = clean.isEmpty ? 0.0 : clean.last;
    final avg = clean.isEmpty ? 0.0 : clean.reduce((a, b) => a + b) / clean.length;
    final minVal = clean.isEmpty ? 0.0 : clean.reduce(math.min);
    final maxVal = clean.isEmpty ? 1.0 : clean.reduce(math.max);
    final span = (maxVal - minVal).abs() < 0.001 ? 1.0 : maxVal - minVal;
    final points = clean.isEmpty
        ? const <double>[0.5, 0.5, 0.5]
        : clean.map((v) => ((v - minVal) / span).clamp(0.12, 0.92).toDouble()).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCardDecoration(tint: color.withValues(alpha: 0.08)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF12214A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                latest > 0 ? '${latest.toStringAsFixed(1)} $unit' : '--',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _SparklinePainter(color: color, points: points),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _smallStat('Average', avg, unit),
              _smallStat('Min', minVal, unit),
              _smallStat('Max', maxVal, unit),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallStat(String label, double value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF7D88A8), fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(
          value > 0 ? '${value.toStringAsFixed(1)} $unit' : '--',
          style: const TextStyle(color: Color(0xFF1F2A44), fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _buildAlertsPage(HealthReading? reading) {
    final currentDanger = _isDangerous(reading);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _softCardDecoration(
            tint: currentDanger ? const Color(0xFFFFEEF2) : const Color(0xFFF0FFF8),
          ),
          child: Row(
            children: [
              Icon(
                currentDanger ? Icons.warning_amber_rounded : Icons.check_circle,
                color: currentDanger ? const Color(0xFFFF315F) : const Color(0xFF16B364),
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  currentDanger
                      ? 'Danger state active. Alert will fire after 2 straight minutes.'
                      : 'No active danger state.',
                  style: const TextStyle(
                    color: Color(0xFF1F2A44),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_alerts.isEmpty)
          _sectionCard(
            child: const Text(
              'No alerts have been triggered yet.',
              style: TextStyle(color: Color(0xFF647090), fontWeight: FontWeight.w700),
            ),
          )
        else
          ..._alerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _sectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFE3EA),
                    child: Icon(Icons.notifications_active, color: Color(0xFFFF315F)),
                  ),
                  title: Text(alert.message, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(_formatDateTime(alert.time)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProfilePage(String? email, AuthService authService, HealthReading? reading) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF6A5CFF).withValues(alpha: 0.14),
                child: Text(
                  (email?.isNotEmpty ?? false) ? email![0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Color(0xFF6A5CFF),
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(email ?? 'Signed in user', style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text('Device path: live/testUser', style: TextStyle(color: Color(0xFF7D88A8))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              reading == null ? Icons.sensors_off : Icons.sensors,
              color: reading == null ? const Color(0xFFF59E0B) : const Color(0xFF16B364),
            ),
            title: const Text('ESP32 live stream', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(reading == null ? 'Waiting for Firebase data' : 'Connected, skin ${reading.skin ? "ON" : "OFF"}'),
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Color(0xFFFF315F)),
            title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w900)),
            onTap: authService.logout,
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCard(String activity) {
    final level = switch (activity.toLowerCase()) {
      'low' => 1,
      'moderate' => 2,
      'high' => 3,
      _ => 0,
    };
    final color = switch (level) {
      0 => const Color(0xFF5A67D8),
      1 => const Color(0xFF18B66A),
      2 => const Color(0xFFFFA62B),
      _ => const Color(0xFFFF315F),
    };
    final label = activity == 'Unknown' ? '--' : activity;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCardDecoration(tint: color.withValues(alpha: 0.08)),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(15),
            ),
            child: _RunningActivityIcon(color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activity',
                  style: TextStyle(
                    color: Color(0xFF1F2A44),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Level $level',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, double value, {double? secondary, String suffix = ''}) {
    final text = secondary == null
        ? '${value.toStringAsFixed(1)}$suffix'
        : '${value.toStringAsFixed(1)}$suffix / ${secondary.toStringAsFixed(1)}$suffix';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _sectionCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          trailing: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCardDecoration(),
      child: child,
    );
  }

  Widget _emptyState(String text) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(18),
        decoration: _softCardDecoration(),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF647090),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7FF),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 16,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.home_rounded, 'Home', 0),
          _navItem(Icons.bar_chart_rounded, 'Trends', 1),
          _navItem(Icons.notifications_none_rounded, 'Alerts', 2),
          _navItem(Icons.person_outline_rounded, 'Profile', 3),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final active = _bottomIndex == index;
    final color = active ? const Color(0xFF5A45FF) : const Color(0xFF7D88A8);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _bottomIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: active ? 84 : 64,
        height: 48,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  HealthStatus _tempStatus(double temp) {
    if (temp >= 36.1 && temp <= 37.2) return HealthStatus.normal;
    if (temp < 35.5 || temp > 38.0) return HealthStatus.critical;
    return HealthStatus.warning;
  }

  bool _isDangerous(HealthReading? reading) {
    if (reading == null) return false;
    final overall = HealthDataService.getOverallStatus(reading.bpm, reading.spo2);
    return overall == HealthStatus.critical || _tempStatus(reading.temp) == HealthStatus.critical;
  }

  void _trackDangerAlert(HealthReading? reading) {
    final dangerous = _isDangerous(reading);
    final now = DateTime.now();

    if (!dangerous) {
      _dangerStartedAt = null;
      _dangerAlertSent = false;
      return;
    }

    _dangerStartedAt ??= now;
    if (_dangerAlertSent) return;

    final elapsed = now.difference(_dangerStartedAt!);
    if (elapsed < const Duration(minutes: 2)) return;

    _dangerAlertSent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || reading == null) return;
      final message = 'Danger alert: vitals stayed critical for 2 minutes.';
      setState(() {
        _alerts.insert(0, _LocalAlert(message: message, time: DateTime.now()));
        _bottomIndex = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$message BPM ${reading.bpm.toStringAsFixed(1)}, SpO2 ${reading.spo2.toStringAsFixed(1)}%, Temp ${reading.temp.toStringAsFixed(1)}C',
          ),
          backgroundColor: const Color(0xFFFF315F),
          duration: const Duration(seconds: 8),
        ),
      );
    });
  }

  String _metricBadgeText(HealthStatus status, String warningLabel) {
    if (status == HealthStatus.warning || status == HealthStatus.critical) {
      return warningLabel;
    }
    return HealthDataService.getStatusText(status);
  }

  BoxDecoration _softCardDecoration({Color tint = Colors.white}) {
    return BoxDecoration(
      color: tint == Colors.white ? Colors.white.withValues(alpha: 0.92) : tint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  String _dateKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.normalText,
    required this.rangeText,
    required this.icon,
    required this.color,
    required this.statusText,
    required this.progress,
    required this.ringValue,
    required this.sparkline,
    this.hot = false,
    this.warm = false,
  });

  final String title;
  final String value;
  final String unit;
  final String normalText;
  final String rangeText;
  final IconData icon;
  final Color color;
  final String statusText;
  final double progress;
  final double ringValue;
  final List<double> sparkline;
  final bool hot;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final background = hot
        ? const Color(0xFFFFF6F8)
        : warm
            ? const Color(0xFFFFFAF2)
            : const Color(0xFFF0FFFC);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1F2A44),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.more_horiz, color: Color(0xFF7D88A8)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                        children: [
                          TextSpan(text: value, style: const TextStyle(fontSize: 40)),
                          TextSpan(text: ' $unit', style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      normalText,
                      style: const TextStyle(
                        color: Color(0xFF7D88A8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: CustomPaint(
                        painter: _SparklinePainter(color: color, points: sparkline),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      rangeText,
                      style: const TextStyle(
                        color: Color(0xFF7D88A8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(112, 112),
                      painter: _RingPainter(color: color, value: ringValue),
                    ),
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 36),
                    ),
        ],
      ),
    ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.75),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 5),
        Text(label),
      ],
    );
  }
}

class _RunningActivityIcon extends StatefulWidget {
  const _RunningActivityIcon({required this.color});

  final Color color;

  @override
  State<_RunningActivityIcon> createState() => _RunningActivityIconState();
}

class _RunningActivityIconState extends State<_RunningActivityIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx = math.sin(_controller.value * math.pi) * 3;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(dx, -dx * 0.25),
              child: Icon(Icons.directions_run, color: widget.color, size: 29),
            ),
            Positioned(
              right: 8,
              bottom: 11,
              child: Container(
                width: 12,
                height: 3,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.color, required this.points});

  final Color color;
  final List<double> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * i / (points.length - 1);
      final y = size.height * (1 - points[i].clamp(0.0, 1.0).toDouble());
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.02)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final lastX = size.width;
    final lastY = size.height * (1 - points.last.clamp(0.0, 1.0).toDouble());
    canvas.drawCircle(Offset(lastX, lastY), 4, Paint()..color = color);
    canvas.drawCircle(Offset(lastX, lastY), 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.points != points;
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.value});

  final Color color;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.10;
    final basePaint = Paint()
      ..color = color.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect.deflate(stroke / 2), -math.pi / 2, math.pi * 2, false, basePaint);
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -math.pi / 2,
      math.pi * 2 * value.clamp(0.0, 1.0).toDouble(),
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.value != value;
  }
}

class _LocalAlert {
  const _LocalAlert({required this.message, required this.time});

  final String message;
  final DateTime time;
}
