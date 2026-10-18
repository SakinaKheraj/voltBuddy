import 'dart:math' as math;

import 'package:voltbuddy/models/simulation_models.dart';

class ChargingAiReport {
  final int score;
  final String scoreLabel;
  final String riskLevel;
  final String confidenceLabel;
  final String summary;
  final String nextAction;
  final String petLine;
  final int totalSessions;
  final int perfectSessions;
  final int overchargeSessions;
  final int criticalStartSessions;
  final int highFinishSessions;
  final int lowStartSessions;
  final int topUpSessions;
  final int nightSessions;
  final WeeklyHabitReport weeklyReport;
  final List<ChargingHabit> habits;
  final List<ChargingRecommendation> recommendations;

  const ChargingAiReport({
    required this.score,
    required this.scoreLabel,
    required this.riskLevel,
    required this.confidenceLabel,
    required this.summary,
    required this.nextAction,
    required this.petLine,
    required this.totalSessions,
    required this.perfectSessions,
    required this.overchargeSessions,
    required this.criticalStartSessions,
    required this.highFinishSessions,
    required this.lowStartSessions,
    required this.topUpSessions,
    required this.nightSessions,
    required this.weeklyReport,
    required this.habits,
    required this.recommendations,
  });

  bool get hasEnoughData => totalSessions >= 3;
}

class WeeklyHabitReport {
  final String dateRange;
  final int totalSessions;
  final int healthySessions;
  final int riskySessions;
  final int score;
  final String trendLabel;
  final String bestHabit;
  final String focusArea;

  const WeeklyHabitReport({
    required this.dateRange,
    required this.totalSessions,
    required this.healthySessions,
    required this.riskySessions,
    required this.score,
    required this.trendLabel,
    required this.bestHabit,
    required this.focusArea,
  });

  bool get hasData => totalSessions > 0;
}

class ChargingHabit {
  final String title;
  final String evidence;
  final HabitSeverity severity;

  const ChargingHabit({
    required this.title,
    required this.evidence,
    required this.severity,
  });
}

class ChargingRecommendation {
  final String title;
  final String body;
  final String impact;
  final RecommendationPriority priority;

  const ChargingRecommendation({
    required this.title,
    required this.body,
    required this.impact,
    required this.priority,
  });
}

enum HabitSeverity { good, watch, risky }

enum RecommendationPriority { low, medium, high }

class ChargingAiService {
  const ChargingAiService();

  ChargingAiReport analyze(List<ChargeSession> sessions) {
    if (sessions.isEmpty) {
      return const ChargingAiReport(
        score: 0,
        scoreLabel: 'Learning',
        riskLevel: 'No data yet',
        confidenceLabel: 'Waiting for first session',
        summary:
            'VoltBuddy AI needs at least one completed charging session before it can personalize your battery health profile.',
        nextAction: 'Charge once, unplug, then open this tab again.',
        petLine: 'I need one real charge log before I can judge your habits.',
        totalSessions: 0,
        perfectSessions: 0,
        overchargeSessions: 0,
        criticalStartSessions: 0,
        highFinishSessions: 0,
        lowStartSessions: 0,
        topUpSessions: 0,
        nightSessions: 0,
        weeklyReport: WeeklyHabitReport(
          dateRange: 'No sessions yet',
          totalSessions: 0,
          healthySessions: 0,
          riskySessions: 0,
          score: 0,
          trendLabel: 'Waiting',
          bestHabit: 'No weekly habit yet',
          focusArea: 'Complete one charging session to unlock this report.',
        ),
        habits: [],
        recommendations: [
          ChargingRecommendation(
            title: 'Collect first session',
            body:
                'Plug in, charge for a while, then unplug. VoltBuddy will turn that session into your first personalized insight.',
            impact: 'Required for personalization',
            priority: RecommendationPriority.high,
          ),
        ],
      );
    }

    final sorted = List<ChargeSession>.from(sessions)
      ..sort((a, b) => _sessionStart(a).compareTo(_sessionStart(b)));
    final total = sorted.length;

    var perfect = 0;
    var overcharge = 0;
    var criticalStart = 0;
    var highFinish = 0;
    var lowStart = 0;
    var topUp = 0;
    var night = 0;

    final sessionsPerDay = <String, int>{};

    for (final session in sorted) {
      sessionsPerDay.update(
        session.startDate,
        (count) => count + 1,
        ifAbsent: () => 1,
      );

      if (session.isPerfectCharge) {
        perfect++;
      }
      if (session.isOvercharge) {
        overcharge++;
      }
      if (session.isCriticalStart) {
        criticalStart++;
      }
      if (session.endPct > 85) {
        highFinish++;
      }
      if (session.startPct > 10 && session.startPct < 20) {
        lowStart++;
      }
      if (session.startPct >= 65 && (session.endPct - session.startPct) <= 20) {
        topUp++;
      }
      if (_looksLikeNightCharge(session)) {
        night++;
      }
    }

    final frequentDays =
        sessionsPerDay.values.where((count) => count >= 4).length;

    final perfectRate = perfect / total;
    final overchargeRate = overcharge / total;
    final criticalRate = criticalStart / total;
    final highFinishRate = highFinish / total;
    final lowStartRate = lowStart / total;
    final topUpRate = topUp / total;
    final nightRate = night / total;
    final frequentDayRate =
        sessionsPerDay.isEmpty ? 0.0 : frequentDays / sessionsPerDay.length;

    final roundedScore = _scoreFromRates(
      total: total,
      perfectRate: perfectRate,
      overchargeRate: overchargeRate,
      criticalRate: criticalRate,
      highFinishRate: highFinishRate,
      lowStartRate: lowStartRate,
      topUpRate: topUpRate,
      nightRate: nightRate,
      frequentDayRate: frequentDayRate,
    );
    final scoreLabel = _scoreLabel(roundedScore, total);
    final riskLevel = _riskLevel(roundedScore, total);
    final confidence = total < 3 ? 'Early signal' : 'Personalized';
    final weeklyReport = _buildWeeklyReport(sorted);
    final habits = _buildHabits(
      total: total,
      perfect: perfect,
      overcharge: overcharge,
      criticalStart: criticalStart,
      highFinish: highFinish,
      lowStart: lowStart,
      topUp: topUp,
      night: night,
      frequentDays: frequentDays,
    );
    final recommendations = _buildRecommendations(
      total: total,
      perfectRate: perfectRate,
      overcharge: overcharge,
      criticalStart: criticalStart,
      highFinish: highFinish,
      lowStart: lowStart,
      topUp: topUp,
      night: night,
      frequentDays: frequentDays,
    );
    final nextAction = recommendations.first.body;
    final petLine = _petLine(
      score: roundedScore,
      total: total,
      overcharge: overcharge,
      criticalStart: criticalStart,
      perfectRate: perfectRate,
    );

    return ChargingAiReport(
      score: roundedScore,
      scoreLabel: scoreLabel,
      riskLevel: riskLevel,
      confidenceLabel: confidence,
      summary:
          'Analyzed $total real charging ${total == 1 ? 'session' : 'sessions'}: $perfect ideal, $overcharge overcharge, $criticalStart deep-discharge start, and $night night-risk pattern.',
      nextAction: nextAction,
      petLine: petLine,
      totalSessions: total,
      perfectSessions: perfect,
      overchargeSessions: overcharge,
      criticalStartSessions: criticalStart,
      highFinishSessions: highFinish,
      lowStartSessions: lowStart,
      topUpSessions: topUp,
      nightSessions: night,
      weeklyReport: weeklyReport,
      habits: habits,
      recommendations: recommendations,
    );
  }

  static int _scoreFromRates({
    required int total,
    required double perfectRate,
    required double overchargeRate,
    required double criticalRate,
    required double highFinishRate,
    required double lowStartRate,
    required double topUpRate,
    required double nightRate,
    required double frequentDayRate,
  }) {
    var score = 100.0;
    score -= overchargeRate * 35;
    score -= criticalRate * 28;
    score -= highFinishRate * 18;
    score -= lowStartRate * 12;
    score -= topUpRate * 8;
    score -= nightRate * 12;
    score -= frequentDayRate * 8;
    score += perfectRate * 10;

    if (total < 3) {
      score -= 6;
    }

    return score.clamp(0, 100).round();
  }

  static WeeklyHabitReport _buildWeeklyReport(List<ChargeSession> sorted) {
    if (sorted.isEmpty) {
      return const WeeklyHabitReport(
        dateRange: 'No sessions yet',
        totalSessions: 0,
        healthySessions: 0,
        riskySessions: 0,
        score: 0,
        trendLabel: 'Waiting',
        bestHabit: 'No weekly habit yet',
        focusArea: 'Complete one charging session to unlock this report.',
      );
    }

    final latest = _dateOnly(_sessionStart(sorted.last));
    final weekStart = latest.subtract(const Duration(days: 6));
    final previousStart = weekStart.subtract(const Duration(days: 7));
    final previousEnd = weekStart.subtract(const Duration(days: 1));

    final currentWeek = sorted.where((session) {
      final date = _dateOnly(_sessionStart(session));
      return !date.isBefore(weekStart) && !date.isAfter(latest);
    }).toList();

    final previousWeek = sorted.where((session) {
      final date = _dateOnly(_sessionStart(session));
      return !date.isBefore(previousStart) && !date.isAfter(previousEnd);
    }).toList();

    final currentMetrics = _SessionMetrics.from(currentWeek);
    final previousMetrics = _SessionMetrics.from(previousWeek);
    final score = currentMetrics.score;
    final previousScore =
        previousMetrics.total == 0 ? null : previousMetrics.score;

    String trend;
    if (previousScore == null) {
      trend = 'First tracked week';
    } else {
      final delta = score - previousScore;
      if (delta >= 8) {
        trend = 'Improving +$delta';
      } else if (delta <= -8) {
        trend = 'Dropped $delta';
      } else {
        trend = 'Stable';
      }
    }

    return WeeklyHabitReport(
      dateRange: '${_shortDate(weekStart)} - ${_shortDate(latest)}',
      totalSessions: currentMetrics.total,
      healthySessions: currentMetrics.perfect,
      riskySessions: currentMetrics.risky,
      score: score,
      trendLabel: trend,
      bestHabit: _weeklyBestHabit(currentMetrics),
      focusArea: _weeklyFocusArea(currentMetrics),
    );
  }

  static String _weeklyBestHabit(_SessionMetrics metrics) {
    if (metrics.total == 0) {
      return 'No weekly habit yet';
    }
    if (metrics.perfect > 0 && metrics.perfect >= metrics.risky) {
      return '${metrics.perfect} healthy ${metrics.perfect == 1 ? 'charge' : 'charges'} in the 20-85 zone.';
    }
    if (metrics.criticalStart == 0) {
      return 'You avoided deep-discharge starts this week.';
    }
    if (metrics.overcharge == 0) {
      return 'You avoided 95%+ overcharging this week.';
    }
    return 'You kept logging consistently, so VoltBuddy can guide you.';
  }

  static String _weeklyFocusArea(_SessionMetrics metrics) {
    if (metrics.total == 0) {
      return 'Complete one charging session to unlock this report.';
    }
    if (metrics.overcharge > 0) {
      return 'Cut the next routine charge at 80-85%.';
    }
    if (metrics.criticalStart > 0 || metrics.lowStart > 0) {
      return 'Plug in before the phone drops below 20%.';
    }
    if (metrics.night > 0) {
      return 'Avoid long late-night charging this week.';
    }
    if (metrics.topUp > 0) {
      return 'Batch small top-ups into one planned charge.';
    }
    if (metrics.perfect >= metrics.total && metrics.total > 0) {
      return 'Maintain the streak with one more healthy charge.';
    }
    return 'Aim for 20-85% on your next routine charge.';
  }

  static String _scoreLabel(int score, int total) {
    if (total < 3) return 'Learning';
    if (score >= 85) return 'Excellent';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Needs attention';
    return 'Risky';
  }

  static String _riskLevel(int score, int total) {
    if (total < 3) return 'Needs more data';
    if (score >= 80) return 'Low risk';
    if (score >= 60) return 'Medium risk';
    return 'High risk';
  }

  static List<ChargingHabit> _buildHabits({
    required int total,
    required int perfect,
    required int overcharge,
    required int criticalStart,
    required int highFinish,
    required int lowStart,
    required int topUp,
    required int night,
    required int frequentDays,
  }) {
    final habits = <ChargingHabit>[];

    if (perfect > 0) {
      habits.add(ChargingHabit(
        title: 'Healthy window usage',
        evidence:
            '$perfect of $total sessions stayed close to the 20-85 range.',
        severity: HabitSeverity.good,
      ));
    }
    if (overcharge > 0) {
      habits.add(ChargingHabit(
        title: 'High-voltage finishing',
        evidence:
            '$overcharge session${overcharge == 1 ? '' : 's'} reached 95% or more.',
        severity: HabitSeverity.risky,
      ));
    } else if (highFinish > 0) {
      habits.add(ChargingHabit(
        title: 'High finish tendency',
        evidence:
            '$highFinish session${highFinish == 1 ? '' : 's'} ended above 85%.',
        severity: HabitSeverity.watch,
      ));
    }
    if (criticalStart > 0 || lowStart > 0) {
      habits.add(ChargingHabit(
        title: 'Low-battery stress',
        evidence:
            '${criticalStart + lowStart} session${criticalStart + lowStart == 1 ? '' : 's'} started below 20%.',
        severity: criticalStart > 0 ? HabitSeverity.risky : HabitSeverity.watch,
      ));
    }
    if (topUp > 0) {
      habits.add(ChargingHabit(
        title: 'Small top-up habit',
        evidence:
            '$topUp session${topUp == 1 ? '' : 's'} started high and added only a small charge.',
        severity: HabitSeverity.watch,
      ));
    }
    if (night > 0) {
      habits.add(ChargingHabit(
        title: 'Night charging risk',
        evidence:
            '$night session${night == 1 ? '' : 's'} looked like a long or late-night charge.',
        severity: HabitSeverity.risky,
      ));
    }
    if (frequentDays > 0) {
      habits.add(ChargingHabit(
        title: 'Frequent charge days',
        evidence:
            '$frequentDays day${frequentDays == 1 ? '' : 's'} had four or more sessions.',
        severity: HabitSeverity.watch,
      ));
    }

    if (habits.isEmpty) {
      habits.add(const ChargingHabit(
        title: 'No risky habit detected',
        evidence:
            'Your current sessions do not show a repeated battery stress pattern.',
        severity: HabitSeverity.good,
      ));
    }

    return habits;
  }

  static List<ChargingRecommendation> _buildRecommendations({
    required int total,
    required double perfectRate,
    required int overcharge,
    required int criticalStart,
    required int highFinish,
    required int lowStart,
    required int topUp,
    required int night,
    required int frequentDays,
  }) {
    final recommendations = <ChargingRecommendation>[];

    if (total < 3) {
      recommendations.add(const ChargingRecommendation(
        title: 'Collect more evidence',
        body:
            'Record at least three completed sessions so the score can separate habits from one-off charging.',
        impact: 'Improves AI confidence',
        priority: RecommendationPriority.high,
      ));
    }
    if (overcharge > 0) {
      recommendations.add(const ChargingRecommendation(
        title: 'Stop before 95%',
        body:
            'Unplug around 80-85% whenever possible; avoid staying near full charge for long periods.',
        impact: 'Reduces high-voltage stress',
        priority: RecommendationPriority.high,
      ));
    } else if (highFinish > 0) {
      recommendations.add(const ChargingRecommendation(
        title: 'Lower your finish target',
        body:
            'Try ending routine charges below 85% unless you need the extra battery for travel or a long day.',
        impact: 'Protects long-term capacity',
        priority: RecommendationPriority.medium,
      ));
    }
    if (criticalStart > 0 || lowStart > 0) {
      recommendations.add(const ChargingRecommendation(
        title: 'Plug in earlier',
        body:
            'Start charging near 20% instead of waiting for very low battery levels.',
        impact: 'Avoids deep-discharge stress',
        priority: RecommendationPriority.high,
      ));
    }
    if (night > 0) {
      recommendations.add(const ChargingRecommendation(
        title: 'Replace overnight charging',
        body:
            'Charge before sleeping or use a shorter morning top-up so the phone spends less time full while plugged in.',
        impact: 'Cuts idle full-charge time',
        priority: RecommendationPriority.high,
      ));
    }
    if (topUp > 0 || frequentDays > 0) {
      recommendations.add(const ChargingRecommendation(
        title: 'Batch small top-ups',
        body:
            'Avoid many tiny plug-ins when the phone is already above 65%; use one planned charge instead.',
        impact: 'Reduces repeated charge cycles',
        priority: RecommendationPriority.medium,
      ));
    }
    if (perfectRate >= 0.6 && total >= 3) {
      recommendations.add(const ChargingRecommendation(
        title: 'Keep this routine',
        body:
            'Most of your sessions are already in the healthy range. Keep aiming for 20-85%.',
        impact: 'Maintains strong score',
        priority: RecommendationPriority.low,
      ));
    }

    if (recommendations.isEmpty) {
      recommendations.add(const ChargingRecommendation(
        title: 'Aim for the 20-85 zone',
        body: 'For normal days, plug in around 20% and unplug around 80-85%.',
        impact: 'Simple baseline habit',
        priority: RecommendationPriority.medium,
      ));
    }

    recommendations
        .sort((a, b) => b.priority.index.compareTo(a.priority.index));
    return recommendations.take(4).toList();
  }

  static String _petLine({
    required int score,
    required int total,
    required int overcharge,
    required int criticalStart,
    required double perfectRate,
  }) {
    if (total < 3) {
      return 'I am still learning your charging style. Give me a few more logs.';
    }
    if (overcharge > 0) {
      return 'Too much full-charge time hurts me. Stop closer to 85%.';
    }
    if (criticalStart > 0) {
      return 'Do not let me starve. Plug in before the battery gets tiny.';
    }
    if (score >= 85 || perfectRate >= 0.6) {
      return 'Strong routine. Keep the 20-85 habit going.';
    }
    return 'Your pattern is fixable. One cleaner charging routine will help.';
  }

  static bool _looksLikeNightCharge(ChargeSession session) {
    final start = _sessionStart(session);
    final end = _sessionEnd(session);
    final duration = end.difference(start);
    final crossesLateNight = _isNightHour(start.hour) ||
        _isNightHour(end.hour) ||
        _crossesNight(start, end);

    return crossesLateNight && (duration.inHours >= 3 || session.endPct >= 90);
  }

  static bool _isNightHour(int hour) {
    return hour >= 22 || hour < 6;
  }

  static bool _crossesNight(DateTime start, DateTime end) {
    final cursor = DateTime(start.year, start.month, start.day, start.hour);
    final totalHours = math.max(0, end.difference(cursor).inHours);
    for (var i = 0; i <= totalHours; i++) {
      if (_isNightHour(cursor.add(Duration(hours: i)).hour)) {
        return true;
      }
    }
    return false;
  }

  static DateTime _dateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  static String _shortDate(DateTime dateTime) {
    return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}';
  }

  static DateTime _sessionStart(ChargeSession session) {
    return _parseDateTime(session.startDate, session.startTime);
  }

  static DateTime _sessionEnd(ChargeSession session) {
    final parsedEnd = _parseDateTime(session.endDate, session.endTime);
    final parsedStart = _sessionStart(session);
    if (parsedEnd.isBefore(parsedStart)) {
      return parsedEnd.add(const Duration(days: 1));
    }
    return parsedEnd;
  }

  static DateTime _parseDateTime(String date, String time) {
    try {
      final dateParts = date.trim().split(RegExp(r'[-/]'));
      final timeParts = time.trim().split(':');
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);
      final hour = timeParts.isNotEmpty ? int.parse(timeParts[0]) : 0;
      final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
      final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class _SessionMetrics {
  final int total;
  final int perfect;
  final int overcharge;
  final int criticalStart;
  final int highFinish;
  final int lowStart;
  final int topUp;
  final int night;
  final int risky;

  const _SessionMetrics({
    required this.total,
    required this.perfect,
    required this.overcharge,
    required this.criticalStart,
    required this.highFinish,
    required this.lowStart,
    required this.topUp,
    required this.night,
    required this.risky,
  });

  factory _SessionMetrics.from(List<ChargeSession> sessions) {
    var perfect = 0;
    var overcharge = 0;
    var criticalStart = 0;
    var highFinish = 0;
    var lowStart = 0;
    var topUp = 0;
    var night = 0;
    var risky = 0;

    for (final session in sessions) {
      final looksLikeNightCharge =
          ChargingAiService._looksLikeNightCharge(session);
      if (session.isPerfectCharge) {
        perfect++;
      }
      if (session.isOvercharge) {
        overcharge++;
      }
      if (session.isCriticalStart) {
        criticalStart++;
      }
      if (session.endPct > 85) {
        highFinish++;
      }
      if (session.startPct > 10 && session.startPct < 20) {
        lowStart++;
      }
      if (session.startPct >= 65 && (session.endPct - session.startPct) <= 20) {
        topUp++;
      }
      if (looksLikeNightCharge) {
        night++;
      }
      if (session.isOvercharge ||
          session.isCriticalStart ||
          looksLikeNightCharge) {
        risky++;
      }
    }

    return _SessionMetrics(
      total: sessions.length,
      perfect: perfect,
      overcharge: overcharge,
      criticalStart: criticalStart,
      highFinish: highFinish,
      lowStart: lowStart,
      topUp: topUp,
      night: night,
      risky: risky,
    );
  }

  int get score {
    if (total == 0) {
      return 0;
    }

    return ChargingAiService._scoreFromRates(
      total: total,
      perfectRate: perfect / total,
      overchargeRate: overcharge / total,
      criticalRate: criticalStart / total,
      highFinishRate: highFinish / total,
      lowStartRate: lowStart / total,
      topUpRate: topUp / total,
      nightRate: night / total,
      frequentDayRate: 0,
    );
  }
}
