import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:voltbuddy/models/simulation_models.dart';

class BatteryRecord {
  final int? id;
  final String timestamp; // ISO-8601 string
  final int level; // 0-100
  final String state; // charging, discharging, full, unknown

  BatteryRecord({this.id, required this.timestamp, required this.level, required this.state});

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp,
        'level': level,
        'state': state,
      };

  static BatteryRecord fromMap(Map<String, dynamic> map) => BatteryRecord(
        id: map['id'] as int?,
        timestamp: map['timestamp'] as String,
        level: map['level'] as int,
        state: map['state'] as String,
      );
}

class BatteryDb {
  static final BatteryDb _instance = BatteryDb._internal();
  factory BatteryDb() => _instance;
  BatteryDb._internal();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final docs = await getApplicationDocumentsDirectory();
    final path = p.join(docs.path, 'battery.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            level INTEGER NOT NULL,
            state TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE charge_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_pct INTEGER NOT NULL,
            start_date TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_pct INTEGER NOT NULL,
            end_date TEXT NOT NULL,
            end_time TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE pending_session (
            id INTEGER PRIMARY KEY,
            start_pct INTEGER NOT NULL,
            start_date TEXT NOT NULL,
            start_time TEXT NOT NULL
          );
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE charge_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              start_pct INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              start_time TEXT NOT NULL,
              end_pct INTEGER NOT NULL,
              end_date TEXT NOT NULL,
              end_time TEXT NOT NULL
            );
          ''');
          await db.execute('''
            CREATE TABLE pending_session (
              id INTEGER PRIMARY KEY,
              start_pct INTEGER NOT NULL,
              start_date TEXT NOT NULL,
              start_time TEXT NOT NULL
            );
          ''');
        }
      },
    );
    return _db!;
  }

  Future<int> insertRecord(BatteryRecord record) async =>
      await (await _database).insert('records', record.toMap());

  Future<List<BatteryRecord>> getAll() async =>
      (await _database).query('records', orderBy: 'id ASC').then((rows) => rows.map(BatteryRecord.fromMap).toList());

  Future<BatteryRecord?> getLatestRecord() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query('records', orderBy: 'id DESC', limit: 1);
    if (maps.isEmpty) return null;
    return BatteryRecord.fromMap(maps.first);
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await (await _database).rawQuery('SELECT COUNT(*) FROM records')) ?? 0;

  // Helpers for finished charge sessions
  Future<int> insertChargeSession(ChargeSession session) async =>
      await (await _database).insert('charge_sessions', {
        'start_pct': session.startPct,
        'start_date': session.startDate,
        'start_time': session.startTime,
        'end_pct': session.endPct,
        'end_date': session.endDate,
        'end_time': session.endTime,
      });

  Future<List<ChargeSession>> getAllChargeSessions() async {
    final List<Map<String, dynamic>> maps = await (await _database).query('charge_sessions', orderBy: 'start_date ASC, start_time ASC');
    return maps.map((map) => ChargeSession(
      startPct: map['start_pct'] as int,
      startDate: map['start_date'] as String,
      startTime: map['start_time'] as String,
      endPct: map['end_pct'] as int,
      endDate: map['end_date'] as String,
      endTime: map['end_time'] as String,
    )).toList();
  }

  Future<int> clearChargeSessions() async =>
      await (await _database).delete('charge_sessions');

  // Helpers for pending sessions
  Future<void> savePendingSession(int startPct, String startDate, String startTime) async {
    final db = await _database;
    await db.delete('pending_session'); // clear previous
    await db.insert('pending_session', {
      'id': 1,
      'start_pct': startPct,
      'start_date': startDate,
      'start_time': startTime,
    });
  }

  Future<Map<String, dynamic>?> getPendingSession() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query('pending_session', where: 'id = 1');
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<void> clearPendingSession() async {
    final db = await _database;
    await db.delete('pending_session');
  }

  Future<int> deleteRecordsUpTo(int maxId) async {
    final db = await _database;
    return await db.delete('records', where: 'id <= ?', whereArgs: [maxId]);
  }

  Future<void> processRawRecordsIntoSessions() async {
    final allRecords = await getAll();
    if (allRecords.length < 2) return;

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

    for (final session in detectedSessions) {
      await insertChargeSession(session);
    }

    if (maxProcessedId != -1) {
      await deleteRecordsUpTo(maxProcessedId);
    }
  }
}
