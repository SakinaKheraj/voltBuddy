
class ChargeSession {
  final int startPct;
  final String startDate;
  final String startTime;
  final int endPct;
  final String endDate;
  final String endTime;
  final String source;

  ChargeSession({
    required this.startPct,
    required this.startDate,
    required this.startTime,
    required this.endPct,
    required this.endDate,
    required this.endTime,
    this.source = 'AC',
  });

  bool get isOvercharge => endPct >= 95;
  bool get isCriticalStart => startPct <= 10;
  bool get isLowStart => startPct >= 11 && startPct <= 19;
  bool get isPerfectCharge => startPct >= 20 && endPct <= 85;

  int get batteryGained => endPct - startPct;

  int get durationMinutes {
    try {
      final start = DateTime.parse('${startDate}T$startTime');
      final end = DateTime.parse('${endDate}T$endTime');
      final diff = end.difference(start).inMinutes;
      return diff >= 0 ? diff : 0;
    } catch (_) {
      return 0;
    }
  }

  double get chargeRatePerHour {
    final mins = durationMinutes;
    if (mins <= 0) return 0.0;
    final gained = batteryGained;
    if (gained <= 0) return 0.0;
    final rate = (gained / (mins / 60.0));
    return rate > 0 ? double.parse(rate.toStringAsFixed(1)) : 0.0;
  }

  String get timeOfDay {
    try {
      final hour = int.parse(startTime.split(':')[0]);
      if (hour >= 5 && hour < 12) return 'Morning';
      if (hour >= 12 && hour < 17) return 'Afternoon';
      if (hour >= 17 && hour < 22) return 'Evening';
      return 'Night';
    } catch (_) {
      return 'Unknown';
    }
  }

  bool get isOvernight {
    try {
      final startHour = int.parse(startTime.split(':')[0]);
      final isNightStart = startHour >= 22 || startHour < 6;
      final isLongDuration = durationMinutes >= 120;
      final isCrossMidnight = startDate != endDate;
      return isNightStart || (isLongDuration && isCrossMidnight);
    } catch (_) {
      return false;
    }
  }

  String get id => '$startDate-$startTime-$endPct';
}

class DailyMetrics {
  final String date;
  int sessions = 0;
  int overcharges = 0;
  int perfects = 0;
  int criticals = 0;
  int totalScore = 0;
  List<String> types = [];
  int? hpAtEndOfDay;
  int? rankAtEndOfDay;
  int? xpAtEndOfDay;
  String? rankName;

  DailyMetrics({required this.date});

  double get averageScore => sessions > 0 ? totalScore / sessions : 0;
}

class WeeklyMetrics {
  final int weekNum;
  final String key; // e.g., "Week 1"
  int xp = 0;
  int hpDelta = 0;
  int over = 0;
  int perf = 0;
  int crit = 0;
  int total = 0;

  WeeklyMetrics({
    required this.weekNum,
    required this.key,
  });

  int get stars {
    if (over == 0 && perf > total * 0.5) return 3;
    if (over <= 2) return 2;
    return 1;
  }
}

class GlobalMetrics {
  int overcharges = 0;
  int criticalStarts = 0;
  int perfectCharges = 0;
  int total = 0;
  int totalXpEarned = 0;

  void reset() {
    overcharges = 0;
    criticalStarts = 0;
    perfectCharges = 0;
    total = 0;
    totalXpEarned = 0;
  }
}
