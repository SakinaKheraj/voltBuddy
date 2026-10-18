import 'package:flutter_test/flutter_test.dart';
import 'package:voltbuddy/models/simulation_models.dart';
import 'package:voltbuddy/services/charging_ai_service.dart';

void main() {
  const service = ChargingAiService();

  ChargeSession session({
    required int startPct,
    required int endPct,
    String date = '2026-08-16',
    String startTime = '10:00:00',
    String endTime = '11:00:00',
  }) {
    return ChargeSession(
      startPct: startPct,
      startDate: date,
      startTime: startTime,
      endPct: endPct,
      endDate: date,
      endTime: endTime,
    );
  }

  test('returns learning report when there is no data', () {
    final report = service.analyze(const []);

    expect(report.totalSessions, 0);
    expect(report.scoreLabel, 'Learning');
    expect(report.weeklyReport.hasData, isFalse);
    expect(report.recommendations.first.title, 'Collect first session');
  });

  test('scores healthy charging patterns highly', () {
    final report = service.analyze([
      session(startPct: 24, endPct: 78),
      session(startPct: 35, endPct: 80, date: '2026-08-17'),
      session(startPct: 28, endPct: 82, date: '2026-08-18'),
    ]);

    expect(report.score, greaterThanOrEqualTo(85));
    expect(report.scoreLabel, 'Excellent');
    expect(report.perfectSessions, 3);
    expect(report.weeklyReport.healthySessions, 3);
    expect(report.weeklyReport.riskySessions, 0);
    expect(
      report.recommendations.any((rec) => rec.title == 'Keep this routine'),
      isTrue,
    );
  });

  test('detects risky overcharging and deep starts', () {
    final report = service.analyze([
      session(
          startPct: 8, endPct: 100, startTime: '23:00:00', endTime: '06:30:00'),
      session(startPct: 12, endPct: 96, date: '2026-08-17'),
      session(startPct: 9, endPct: 92, date: '2026-08-18'),
    ]);

    expect(report.score, lessThan(60));
    expect(report.overchargeSessions, 2);
    expect(report.criticalStartSessions, 2);
    expect(report.nightSessions, 1);
    expect(report.weeklyReport.riskySessions, 3);
    expect(
      report.recommendations.any((rec) => rec.title == 'Stop before 95%'),
      isTrue,
    );
    expect(
      report.recommendations.any((rec) => rec.title == 'Plug in earlier'),
      isTrue,
    );
  });

  test('flags repeated small top-ups', () {
    final report = service.analyze([
      session(startPct: 70, endPct: 82),
      session(startPct: 72, endPct: 84, date: '2026-08-17'),
      session(startPct: 68, endPct: 83, date: '2026-08-18'),
    ]);

    expect(report.topUpSessions, 3);
    expect(
      report.recommendations.any((rec) => rec.title == 'Batch small top-ups'),
      isTrue,
    );
  });
}
