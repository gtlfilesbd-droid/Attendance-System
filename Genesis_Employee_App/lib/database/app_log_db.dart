import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Phase 2: SQLite database for persistent app logs (offline-first).
class AppLogDb {
  static Database? _db;
  static const String _table = 'app_logs';
  static const int _maxRows = 50000;
  static const int _maxAgeDays = 7;

  static Future<Database> _getDb() async {
    if (_db != null && (_db!.isOpen)) return _db!;
    final path = await getDatabasesPath();
    final dbPath = join(path, 'genesis_app_logs.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            level TEXT NOT NULL,
            category TEXT NOT NULL,
            message TEXT NOT NULL,
            extra_json TEXT,
            stack_trace TEXT,
            duration_ms INTEGER,
            device_android_version TEXT,
            device_brand TEXT,
            device_model TEXT,
            uploaded INTEGER DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_app_logs_ts ON $_table(timestamp)');
        await db.execute('CREATE INDEX idx_app_logs_uploaded ON $_table(uploaded)');
        await db.execute('CREATE INDEX idx_app_logs_category ON $_table(category)');
      },
    );
    return _db!;
  }

  /// Insert a log row. [timestamp] = milliseconds since epoch.
  static Future<int> insert({
    required int timestamp,
    required String level,
    required String category,
    required String message,
    String? extraJson,
    String? stackTrace,
    int? durationMs,
    String? deviceAndroidVersion,
    String? deviceBrand,
    String? deviceModel,
  }) async {
    final db = await _getDb();
    await _rotateIfNeeded(db);
    return db.insert(_table, {
      'timestamp': timestamp,
      'level': level,
      'category': category,
      'message': message,
      'extra_json': extraJson,
      'stack_trace': stackTrace,
      'duration_ms': durationMs,
      'device_android_version': deviceAndroidVersion,
      'device_brand': deviceBrand,
      'device_model': deviceModel,
      'uploaded': 0,
    });
  }

  static Future<void> _rotateIfNeeded(Database db) async {
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_table'));
    if (count == null || count < _maxRows) return;
    final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays)).millisecondsSinceEpoch;
    await db.delete(_table, where: 'timestamp < ?', whereArgs: [cutoff]);
  }

  /// Get up to [limit] logs that are not yet uploaded, ordered by timestamp.
  static Future<List<Map<String, dynamic>>> getUnuploaded({int limit = 500}) async {
    final db = await _getDb();
    return db.query(_table, where: 'uploaded = 0', orderBy: 'timestamp ASC', limit: limit);
  }

  /// Mark logs as uploaded by ids.
  static Future<void> markUploaded(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _getDb();
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate('UPDATE $_table SET uploaded = 1 WHERE id IN ($placeholders)', ids);
  }

  /// Get logs in last [hours] for debug export (e.g. 24).
  static Future<List<Map<String, dynamic>>> getRecentHours(int hours) async {
    final db = await _getDb();
    final cutoff = DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch;
    return db.query(_table, where: 'timestamp >= ?', whereArgs: [cutoff], orderBy: 'timestamp ASC');
  }

  static Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
