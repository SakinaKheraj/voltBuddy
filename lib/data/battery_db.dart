import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          level INTEGER NOT NULL,
          state TEXT NOT NULL
        );
      ''');
    });
    return _db!;
  }

  Future<int> insertRecord(BatteryRecord record) async =>
      await (await _database).insert('records', record.toMap());

  Future<List<BatteryRecord>> getAll() async =>
      (await _database).query('records', orderBy: 'id ASC').then((rows) => rows.map(BatteryRecord.fromMap).toList());

  Future<int> count() async =>
      Sqflite.firstIntValue(await (await _database).rawQuery('SELECT COUNT(*) FROM records')) ?? 0;
}
