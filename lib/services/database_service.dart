import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';

/// Pangkalan data tempatan (SQLite) untuk Sejarah & Gagal.
///
/// B24: skema v2 — indeks sessions(started_at), lajur discord_code pada
/// failures, onUpgrade scaffolding, transaksi untuk hapus berbilang baris,
/// dan pembersihan rekod lama (prune).
class DatabaseService {
  DatabaseService._();
  static DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    final d = _db;
    if (d != null && d.isOpen) return d;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'discord_media_sender.db'),
      version: 2,
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
            discord_code INTEGER,
            error_message TEXT NOT NULL,
            mode TEXT NOT NULL,
            target TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_failures_session ON failures(session_id)');
        await db.execute('CREATE INDEX idx_failures_created ON failures(created_at DESC)');
        await db.execute('CREATE INDEX idx_failures_path ON failures(file_path)');
        await db.execute('CREATE INDEX idx_sessions_started ON sessions(started_at DESC)');
      },
      // B24: scaffolding onUpgrade untuk perubahan skema masa depan.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v2: lajur discord_code + indeks baharu.
          final cols = await db.query('failures', limit: 1);
          if (cols.isNotEmpty && !cols.first.containsKey('discord_code')) {
            await db.execute('ALTER TABLE failures ADD COLUMN discord_code INTEGER');
          } else if (cols.isEmpty) {
            // Jadual kosong — tambah lajur tanpa semak baris.
            try {
              await db.execute('ALTER TABLE failures ADD COLUMN discord_code INTEGER');
            } catch (_) {}
          }
          try {
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_failures_path ON failures(file_path)');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at DESC)');
          } catch (_) {}
        }
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
  /// aplikasi ditutup semasa hantaran. Dipanggil sekali semasa app
  /// dimulakan supaya Sejarah tidak memaparkan "running" selamanya.
  /// Sekali gus: B24 — buang rekod lama (kekal 500 sesi / 5000 kegagalan).
  Future<int> healStaleSessions() async {
    final db = await database;
    var changed = await db.update(
      'sessions',
      {
        'status': 'cancelled',
        'ended_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: "status IN ('running', 'berjalan')",
    );
    try {
      await pruneOldRecords();
    } catch (_) {}
    return changed;
  }

  /// B24: simpan maksimum [keepSessions] sesi & [keepFailures] kegagalan.
  Future<void> pruneOldRecords({int keepSessions = 500, int keepFailures = 5000}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'sessions',
        where:
            'id NOT IN (SELECT id FROM sessions ORDER BY started_at DESC LIMIT ?)',
        whereArgs: [keepSessions],
      );
      await txn.delete(
        'failures',
        where:
            'id NOT IN (SELECT id FROM failures ORDER BY created_at DESC LIMIT ?)',
        whereArgs: [keepFailures],
      );
    });
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

  /// B24: hapus berbilang sesi dalam SATU transaksi.
  Future<void> deleteSessions(Iterable<int> ids) async {
    final db = await database;
    final list = ids.toList();
    if (list.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in list) {
        batch.delete('sessions', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearSessions() async {
    final db = await database;
    await db.delete('sessions');
  }

  // ---------------------------------------------------------- gagal

  /// B04: tulis rekod kegagalan secara ATOMIK (transaksi) — baris dengan
  /// file_path yang SAMA dikemas kini (bukan pendua baharu). Retry yang
  /// gagal semula tidak lagi mengumpul baris berulang.
  Future<void> addFailures(List<FailedRecord> list) async {
    if (list.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final f in list) {
        final existing = await txn.query(
          'failures',
          where: 'file_path = ?',
          whereArgs: [f.filePath],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final id = existing.first['id'] as int;
          await txn.update(
            'failures',
            _failureMap(f),
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.insert('failures', _failureMap(f));
        }
      }
    });
  }

  Map<String, dynamic> _failureMap(FailedRecord f) => f.toMap()..remove('id');

  /// B04: buang rekod gagal bagi laluan yang BERJAYA dihantar semula —
  /// dipanggil apabila batch berjaya (retry membersihkan baris lamanya).
  /// Dijalankan dalam transaksi.
  Future<void> deleteFailuresByPaths(Iterable<String> paths) async {
    final db = await database;
    final list = paths.toSet().toList();
    if (list.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final path in list) {
        batch.delete('failures', where: 'file_path = ?', whereArgs: [path]);
      }
      await batch.commit(noResult: true);
    });
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

  /// B24: hapus berbilang kegagalan dalam SATU transaksi.
  Future<void> deleteFailures(Iterable<int> ids) async {
    final db = await database;
    final list = ids.toList();
    if (list.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in list) {
        batch.delete('failures', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearFailures() async {
    final db = await database;
    await db.delete('failures');
  }

  Future<void> clearAll() async {
    // B24: transaksi tunggal — kedua-dua jadual sekali gus.
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('failures');
      await txn.delete('sessions');
    });
  }
}
