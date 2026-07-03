class BatteryRecord {
  final int? id;
  final String timestamp;
  final int level;
  final String state;

  BatteryRecord({this.id, required this.timestamp, required this.level, required this.state});
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

  @override
  String toString() => 'Session($startPct% -> $endPct%, Start: $startDate $startTime, End: $endDate $endTime)';
}

void main() {
  final List<BatteryRecord> records = [
    // Online Session 1 (proper charging and discharging records)
    BatteryRecord(id: 1, timestamp: '2026-07-02T12:00:00Z', level: 40, state: 'charging'),
    BatteryRecord(id: 2, timestamp: '2026-07-02T12:05:00Z', level: 45, state: 'charging'),
    BatteryRecord(id: 3, timestamp: '2026-07-02T12:10:00Z', level: 50, state: 'charging'),
    BatteryRecord(id: 4, timestamp: '2026-07-02T12:15:00Z', level: 50, state: 'discharging'),
    
    // Discharging records in between
    BatteryRecord(id: 5, timestamp: '2026-07-02T12:20:00Z', level: 49, state: 'discharging'),
    BatteryRecord(id: 6, timestamp: '2026-07-02T12:25:00Z', level: 48, state: 'discharging'),

    // Offline Session 2 (plugged in, charged, and unplugged while app was completely closed, no charging records recorded)
    BatteryRecord(id: 7, timestamp: '2026-07-02T13:00:00Z', level: 65, state: 'discharging'),
  ];

  print('=== Running parser ===');
  final result = processRawRecordsIntoSessions(records);
  print('Detected sessions:');
  for (final s in result.sessions) {
    print(s);
  }
  print('Max processed ID: ${result.maxProcessedId}');
}

class ParseResult {
  final List<ChargeSession> sessions;
  final int maxProcessedId;
  ParseResult(this.sessions, this.maxProcessedId);
}

ParseResult processRawRecordsIntoSessions(List<BatteryRecord> allRecords) {
  if (allRecords.length < 2) return ParseResult([], -1);

  List<ChargeSession> detectedSessions = [];
  int maxProcessedId = -1;

  int? sessionStartLevel;
  BatteryRecord? sessionStartRecord;
  BatteryRecord? lastChargingRecord;

  for (int i = 0; i < allRecords.length; i++) {
    final rec = allRecords[i];
    final isChargingNow = rec.state == 'charging' || rec.state == 'full';
    final prevRec = i > 0 ? allRecords[i - 1] : null;

    // Check for offline/gap charging session:
    // If the level increased, but neither record is currently charging
    if (prevRec != null && rec.level > prevRec.level + 1 && !isChargingNow) {
      try {
        final startDt = DateTime.parse(prevRec.timestamp);
        final endDt = DateTime.parse(rec.timestamp);

        final session = ChargeSession(
          startPct: prevRec.level,
          startDate: "${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}",
          startTime: "${startDt.hour.toString().padLeft(2, '0')}:${startDt.minute.toString().padLeft(2, '0')}:${startDt.second.toString().padLeft(2, '0')}",
          endPct: rec.level,
          endDate: "${endDt.year}-${endDt.month.toString().padLeft(2, '0')}-${endDt.day.toString().padLeft(2, '0')}",
          endTime: "${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}:${endDt.second.toString().padLeft(2, '0')}",
        );
        detectedSessions.add(session);
      } catch (_) {}

      if (rec.id != null && rec.id! > maxProcessedId) {
        maxProcessedId = rec.id!;
      }

      sessionStartLevel = null;
      sessionStartRecord = null;
      lastChargingRecord = null;
      continue;
    }

    if (isChargingNow) {
      if (sessionStartLevel == null) {
        sessionStartLevel = rec.level;
        sessionStartRecord = rec;
      }
      lastChargingRecord = rec;
    } else {
      if (sessionStartLevel != null && lastChargingRecord != null) {
        final endLevel = rec.level;
        final endRecord = rec;

        if (endLevel > sessionStartLevel) {
          try {
            final startDt = DateTime.parse(sessionStartRecord!.timestamp);
            final endDt = DateTime.parse(endRecord.timestamp);

            final session = ChargeSession(
              startPct: sessionStartLevel,
              startDate: "${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}",
              startTime: "${startDt.hour.toString().padLeft(2, '0')}:${startDt.minute.toString().padLeft(2, '0')}:${startDt.second.toString().padLeft(2, '0')}",
              endPct: endLevel,
              endDate: "${endDt.year}-${endDt.month.toString().padLeft(2, '0')}-${endDt.day.toString().padLeft(2, '0')}",
              endTime: "${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}:${endDt.second.toString().padLeft(2, '0')}",
            );
            detectedSessions.add(session);
          } catch (_) {}
        }

        if (endRecord.id != null && endRecord.id! > maxProcessedId) {
          maxProcessedId = endRecord.id!;
        }

        sessionStartLevel = null;
        sessionStartRecord = null;
        lastChargingRecord = null;
      }
    }
  }

  return ParseResult(detectedSessions, maxProcessedId);
}
