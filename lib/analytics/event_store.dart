import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Column order used for storage and CSV export.
const List<String> kEventColumns = [
  'id',
  'launch_id',
  'session_id',
  'session_seq',
  'source',
  'ts_utc_ms',
  'ts_local',
  'mono_ms',
  'event',
  'user_action',
  'tab',
  'target',
  'props',
  'battery_pct',
  'battery_state',
  'is_charging',
  'persona',
  'species',
  'hp',
  'xp',
  'rank_index',
  'app_version',
];

abstract class EventStore {
  Future<void> insertAll(List<Map<String, Object?>> rows);
  Future<List<Map<String, Object?>>> all();
  Future<List<Map<String, Object?>>> latest(int limit);
  Future<int> count();
}

/// Events live in their own database file so the existing charging database
/// (battery.db) is never migrated, and "Clear All Data" does not erase them.
class SqfliteEventStore implements EventStore {
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final docs = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(docs.path, 'interaction_events.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            launch_id TEXT,
            session_id TEXT,
            session_seq INTEGER,
            source TEXT NOT NULL,
            ts_utc_ms INTEGER NOT NULL,
            ts_local TEXT NOT NULL,
            mono_ms INTEGER,
            event TEXT NOT NULL,
            user_action INTEGER NOT NULL,
            tab TEXT,
            target TEXT,
            props TEXT,
            battery_pct INTEGER,
            battery_state TEXT,
            is_charging INTEGER,
            persona TEXT,
            species TEXT,
            hp INTEGER,
            xp INTEGER,
            rank_index INTEGER,
            app_version TEXT
          );
        ''');
      },
    );
    return _db!;
  }

  @override
  Future<void> insertAll(List<Map<String, Object?>> rows) async {
    final db = await _database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert('events', row);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<Map<String, Object?>>> all() async =>
      (await _database).query('events', orderBy: 'id ASC');

  @override
  Future<List<Map<String, Object?>>> latest(int limit) async =>
      (await _database).query('events', orderBy: 'id DESC', limit: limit);

  @override
  Future<int> count() async =>
      Sqflite.firstIntValue(
          await (await _database).rawQuery('SELECT COUNT(*) FROM events')) ??
      0;
}

/// Used by unit tests.
class MemoryEventStore implements EventStore {
  final List<Map<String, Object?>> rows = [];

  @override
  Future<void> insertAll(List<Map<String, Object?>> newRows) async {
    for (final row in newRows) {
      rows.add({...row, 'id': rows.length + 1});
    }
  }

  @override
  Future<List<Map<String, Object?>>> all() async => List.of(rows);

  @override
  Future<List<Map<String, Object?>>> latest(int limit) async =>
      rows.reversed.take(limit).toList();

  @override
  Future<int> count() async => rows.length;
}
