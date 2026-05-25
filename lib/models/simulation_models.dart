
enum ChargeEventType {
  powerConnected,
  powerDisconnected,
}

class LogEntry {
  final int userId;
  final ChargeEventType eventType;
  final int percentage;
  final String date; // yyyy-MM-dd
  final String time; // HH:mm:ss
  final String timezone;

  LogEntry({
    required this.userId,
    required this.eventType,
    required this.percentage,
    required this.date,
    required this.time,
    required this.timezone,
  });

  factory LogEntry.fromCsvLine(String line) {
    final cols = line.trim().split(',');
    if (cols.length < 5) {
      throw FormatException('Invalid CSV line: $line');
    }
    final userId = int.parse(cols[0]);
    final eventType = cols[1] == 'power_connected'
        ? ChargeEventType.powerConnected
        : ChargeEventType.powerDisconnected;
    final percentage = int.parse(cols[2]);
    final date = cols[3];
    final time = cols[4];
    final timezone = cols.length > 5 ? cols[5] : '';

    return LogEntry(
      userId: userId,
      eventType: eventType,
      percentage: percentage,
      date: date,
      time: time,
      timezone: timezone,
    );
  }
}

class ChargeSession {
  final int startPct;
  final String startDate;
  final String startTime;
  final int endPct;
  final String endDate;
  final String endTime;

  ChargeSession({
    required this.startPct,
    required this.startDate,
    required this.startTime,
    required this.endPct,
    required this.endDate,
    required this.endTime,
  });

  bool get isOvercharge => endPct >= 95;
  bool get isCriticalStart => startPct <= 10;
  bool get isPerfectCharge => startPct >= 20 && endPct <= 85;

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
