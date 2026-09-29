import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Pangkalan data tempatan (SQLite) untuk Sejarah & Gagal.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    final d = _db;
    if (d != null && d.isOpen) return d;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'discord_media_sender.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            mode TEXT NOT NULL,
            target TEXT NOT NULL,
            total_files INTEGER NOT NULL,
            success INTEGER NOT NULL,
            failed INTEGER NOT NULL,
            status TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE failures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER,
            file_name TEXT NOT NULL,
            file_path TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            batch_index INTEGER NOT NULL,
            http_code INTEGER,
            error_message TEXT NOT NULL,
            mode TEXT NOT NULL,
            target TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_failures_session ON failures(session_id)');
        await db.execute('CREATE INDEX idx_failures_created ON failures(created_at DESC)');
      },
    );
    return _db!;
  }

  // ------------------------------------------------------------ sesi

  Future<int> createSession(SessionRecord s) async {
    final db = await database;
    return db.insert('sessions', s.toMap());
  }

  Future<void> finishSession(
    int id, {
    required int success,
    required int failed,
    required String status,
  }) async {
    final db = await database;
    await db.update(
      'sessions',
      {'ended_at': DateTime.now().millisecondsSinceEpoch, 'success': success, 'failed': failed, 'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Pulihkan sesi yang tersangkut pada status 'running' — berlaku apabila
  /// aplikasi ditutup semasa hantaran (hantaran tidak kekal selepas app
  /// dimatikan). Dipanggil sekali semasa app dimulakan supaya Sejarah
  /// tidak memaparkan "running" selamanya.
  Future<int> healStaleSessions() async {
    final db = await database;
    return db.update(
      'sessions',
      {
        'status': 'cancelled',
        'ended_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: "status IN ('running', 'berjalan')",
    );
  }

  Future<List<SessionRecord>> sessions({int limit = 500}) async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'started_at DESC', limit: limit);
    return rows.map(SessionRecord.fromMap).toList();
  }

  Future<void> deleteSession(int id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearSessions() async {
    final db = await database;
    await db.delete('sessions');
  }

  // ---------------------------------------------------------- gagal

  Future<void> addFailures(List<FailedRecord> list) async {
    if (list.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final f in list) {
      batch.insert('failures', f.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<FailedRecord>> failures({int? sessionId, int limit = 1000}) async {
    final db = await database;
    final rows = await db.query(
      'failures',
      where: sessionId != null ? 'session_id = ?' : null,
      whereArgs: sessionId != null ? [sessionId] : null,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(FailedRecord.fromMap).toList();
  }

  Future<void> deleteFailure(int id) async {
    final db = await database;
    await db.delete('failures', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearFailures() async {
    final db = await database;
    await db.delete('failures');
  }

  Future<void> clearAll() async {
    await clearFailures();
    await clearSessions();
  }
}
