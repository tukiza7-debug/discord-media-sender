import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/models.dart';

/// Pangkalan data tempatan (SQLite) untuk Sejarah & Gagal.
///
/// B24: skema v2 — indeks sessions(started_at), lajur discord_code pada
/// failures, onUpgrade scaffolding, transaksi untuk hapus berbilang baris,
/// dan pembersihan rekod lama (prune).
/// v3 — lajur `reason` pada sessions (sebab status bukan-completed, 4a).
/// v4 — jadual `session_files` (giliran tahan-lama, 2b) + lajur
/// `heartbeat_at` pada sessions (2d). WAL + busy_timeout untuk akses
/// merentas isolate (2c).
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
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // 2c: WAL membolehkan main isolate & task isolate menulis serentak
        // tanpa saling mengunci; busy_timeout menunggu kunci sebentar.
        try {
          await db.execute('PRAGMA journal_mode = WAL');
        } catch (_) {}
        try {
          await db.execute('PRAGMA busy_timeout = 4000');
        } catch (_) {}
      },
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
            status TEXT NOT NULL,
            reason TEXT,
            heartbeat_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE session_files (
            session_id INTEGER NOT NULL,
            idx INTEGER NOT NULL,
            path TEXT NOT NULL,
            name TEXT NOT NULL,
            size INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            error TEXT,
            PRIMARY KEY (session_id, idx),
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_session_files_path ON session_files(session_id, path)');
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
        // v3: lajur reason pada sessions — sesi lama (sebelum kemas kini
        // ini) kekal tanpa sebab (reason == null). Lajur mungkin sudah
        // wujud pada pemasaran tertentu — cuba dan abaikan kegagalan.
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE sessions ADD COLUMN reason TEXT');
          } catch (_) {}
        }
        // v4: jadual giliran tahan-lama + lajur heartbeat (2b/2d).
        if (oldVersion < 4) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS session_files (
                session_id INTEGER NOT NULL,
                idx INTEGER NOT NULL,
                path TEXT NOT NULL,
                name TEXT NOT NULL,
                size INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                error TEXT,
                PRIMARY KEY (session_id, idx),
                FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
              )
            ''');
            await db.execute(
                'CREATE INDEX IF NOT EXISTS idx_session_files_path ON session_files(session_id, path)');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE sessions ADD COLUMN heartbeat_at INTEGER');
          } catch (_) {}
        }
      },
    );
    return _db!;
  }

  /// 2c: cuba semula secara ringkas apabila pangkalan data sedang dikunci
  /// oleh isolate lain (WAL + busy_timeout sudah membantu; ini lapisan
  /// pertahanan terakhir). Ralat lain ditembusi terus.
  static bool _isLockedError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('locked') || s.contains('busy');
  }

  Future<T> _retryLocked<T>(Future<T> Function() op) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await op();
      } catch (e) {
        if (attempt >= 3 || !_isLockedError(e)) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
  }

  // ------------------------------------------------------------ sesi

  /// 2e: pengaman SESI TUNGGAL di peringkat pangkalan data — mula baharu
  /// ditolak jika sudah wujud sesi 'running'. (Sambung semula TIDAK melalui
  /// kaedah ini — ia mengguna semula sesi sedia ada.)
  Future<int> createSession(SessionRecord s) async {
    final db = await database;
    final running = await db.query('sessions',
        columns: ['id'],
        where: "status IN ('running', 'berjalan')",
        limit: 1);
    if (running.isNotEmpty) {
      throw StateError('A running session already exists');
    }
    return db.insert('sessions', s.toMap());
  }

  Future<void> finishSession(
    int id, {
    required int success,
    required int failed,
    required String status,
    String? reason,
  }) async {
    final db = await database;
    final map = <String, dynamic>{
      'ended_at': DateTime.now().millisecondsSinceEpoch,
      'success': success,
      'failed': failed,
      'status': status,
    };
    // Tulis sebab hanya apabila ada — sebab sedia ada tidak ditindih null.
    if (reason != null) map['reason'] = reason;
    await db.update('sessions', map, where: 'id = ?', whereArgs: [id]);
  }

  /// 2d: pulihkan sesi yang tersangkut pada status 'running' — HANYA jika
  /// servis TIDAK berjalan DAN denyar (heartbeat) lebih lama daripada 2
  /// minit. Sesi dgn baris pending TIDAK dibatalkan senyap: ia dibiarkan
  /// 'running' dan dipaparkan prompt "Resume sending?" pada app dibuka.
  /// Kembalikan senarai sesi yang BOLEH disambung semula (id + baki fail).
  /// Sekali gus: B24 — buang sesi lama (kekal 500 sesi).
  Future<List<ResumableSession>> healStaleSessions({required bool serviceAlive}) async {
    final db = await database;
    // Servis sedang berjalan — jangan sentuh sesi hidup mana-mana.
    if (serviceAlive) {
      try {
        await pruneOldRecords();
      } catch (_) {}
      return const [];
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleBefore = now - AppLimits.heartbeatStaleMs;
    final rows = await db.query('sessions',
        columns: ['id', 'total_files', 'success', 'failed'],
        where: "status IN ('running', 'berjalan') AND "
            '(heartbeat_at IS NULL OR heartbeat_at < ?)',
        whereArgs: [staleBefore]);
    final resumable = <ResumableSession>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final pending = await pendingFileCount(id);
      if (pending > 0) {
        // 2d: jangan batalkan senyap — tunggu keputusan pengguna.
        resumable.add(ResumableSession(
          sessionId: id,
          pendingCount: pending,
          totalFiles: (r['total_files'] ?? 0) as int,
        ));
      } else {
        await db.update(
          'sessions',
          {
            'status': 'cancelled',
            'ended_at': now,
            'reason': 'The app was closed or stopped while this session was '
                'running. It was not cancelled by the user. Files not yet '
                'sent were not delivered.',
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    try {
      await pruneOldRecords();
    } catch (_) {}
    return resumable;
  }

  /// Sesi yang sedang berjalan (untuk pengaman sesi tunggal & UI).
  Future<SessionRecord?> runningSession() async {
    final db = await database;
    final rows = await db.query('sessions',
        where: "status IN ('running', 'berjalan')",
        orderBy: 'started_at DESC',
        limit: 1);
    return rows.isEmpty ? null : SessionRecord.fromMap(rows.first);
  }

  // ------------------------------------------------- giliran tahan-lama

  /// 2b: cipta SEMUA baris giliran bagi satu sesi — secara cebisan transaksi
  /// supaya 20,000+ fail tidak membekukan UI. Kekalkan laju: batch commit
  /// tanpa hasil.
  Future<void> createSessionFiles(int sessionId, List<MediaItem> items) async {
    const chunkSize = 1000;
    for (var start = 0; start < items.length; start += chunkSize) {
      final end = (start + chunkSize) > items.length
          ? items.length
          : start + chunkSize;
      await _retryLocked(() async {
        final db = await database;
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var i = start; i < end; i++) {
            final m = items[i];
            batch.insert('session_files', SessionFileRecord(
              sessionId: sessionId,
              idx: i,
              path: m.path,
              name: m.name,
              size: m.sizeBytes,
            ).toMap());
          }
          await batch.commit(noResult: true);
        });
      });
      // Beri peluang kepada event loop antara cebisan (UI kekal responsif).
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Baris PENDING sahaja — sambung semula tidak pernah menghantar semula
  /// baris yang sudah 'sent' (2d).
  Future<List<SessionFileRecord>> pendingSessionFiles(int sessionId) async {
    final db = await database;
    final rows = await db.query('session_files',
        where: 'session_id = ? AND status = ?',
        whereArgs: [sessionId, 'pending'],
        orderBy: 'idx');
    return rows.map(SessionFileRecord.fromMap).toList();
  }

  Future<int> pendingFileCount(int sessionId) async {
    final db = await database;
    final r = await db.query('session_files',
        columns: ['COUNT(*) AS n'],
        where: 'session_id = ? AND status = ?',
        whereArgs: [sessionId, 'pending']);
    return (r.first['n'] ?? 0) as int;
  }

  /// Kiraan baris mengikut status (progres diterbitkan daripada DB, 2b).
  Future<Map<String, int>> sessionFileStatusCounts(int sessionId) async {
    final db = await database;
    final rows = await db.query('session_files',
        columns: ['status', 'COUNT(*) AS n'],
        where: 'session_id = ?',
        groupBy: 'status');
    return {
      for (final r in rows) (r['status'] as String): (r['n'] ?? 0) as int,
    };
  }

  /// Kemas kini status baris selepas SETIAP batch (task isolate, 2b).
  /// [paths] dicebis — SQLITE_MAX_VARIABLE_NUMBER selamat.
  Future<void> markSessionFiles(
    int sessionId,
    Iterable<String> paths, {
    required String status,
    String? error,
  }) async {
    final list = paths.toList();
    const chunkSize = 400;
    for (var start = 0; start < list.length; start += chunkSize) {
      final end = (start + chunkSize) > list.length
          ? list.length
          : start + chunkSize;
      final chunk = list.sublist(start, end);
      await _retryLocked(() async {
        final db = await database;
        await db.update(
          'session_files',
          {'status': status, 'error': error},
          where: 'session_id = ? AND path IN (${chunk.map((_) => '?').join(',')})',
          whereArgs: [sessionId, ...chunk],
        );
      });
    }
  }

  /// 2d: baki baris pending sesi yang tamat dibatalkan/dibuang → 'skipped'
  /// (tidak pernah hilang senyap — boleh dihantar semula dari senarai).
  Future<void> skipRemainingSessionFiles(int sessionId) async {
    await _retryLocked(() async {
      final db = await database;
      await db.update(
        'session_files',
        {'status': 'skipped', 'error': 'Not sent'},
        where: 'session_id = ? AND status = ?',
        whereArgs: [sessionId, 'pending'],
      );
    });
  }

  /// Semua laluan fail bagi satu sesi (untuk pembersihan folder sementara).
  Future<List<String>> sessionFilePaths(int sessionId) async {
    final db = await database;
    final rows = await db.query('session_files',
        columns: ['path'], where: 'session_id = ?', whereArgs: [sessionId]);
    return rows.map((r) => (r['path'] ?? '') as String).toList();
  }

  /// Semua laluan fail milik sesi yang masih 'running' — folder sementara
  /// ZIP yang mengandungi laluan ini DILINDUNGI daripada pembersihan (2d).
  Future<Set<String>> runningSessionFilePaths() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT sf.path AS path
      FROM session_files sf
      JOIN sessions s ON s.id = sf.session_id
      WHERE s.status IN ('running', 'berjalan')
    ''');
    return {for (final r in rows) (r['path'] ?? '') as String};
  }

  /// 2d: denyar sesi — dikemas kini task isolate sekurang-kurangnya setiap
  /// 5 saat semasa sesi berjalan.
  Future<void> touchHeartbeat(int sessionId) async {
    await _retryLocked(() async {
      final db = await database;
      await db.update(
        'sessions',
        {'heartbeat_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ? AND status IN (\'running\', \'berjalan\')',
        whereArgs: [sessionId],
      );
    });
  }

  /// Tandakan baris baki (pending) sesi ini sebagai skipped + kembalikan
  /// kiraan yang dilangkau (dipanggil semasa batal/discard).
  Future<int> finalizeUnsentRows(int sessionId) async {
    final n = await pendingFileCount(sessionId);
    if (n > 0) await skipRemainingSessionFiles(sessionId);
    return n;
  }

  /// B24: simpan maksimum [keepSessions] sesi. Kegagalan TIDAK dipangkas
  /// (3f) — dengan bilangan fail tak terhad, rekod gagal boleh jadi
  /// sangat banyak dan mesti kekal untuk Cuba Semula.
  Future<void> pruneOldRecords({int keepSessions = 500}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'sessions',
        where:
            'id NOT IN (SELECT id FROM sessions ORDER BY started_at DESC LIMIT ?)',
        whereArgs: [keepSessions],
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

  /// 3f: limit lalai NULL = pulangkan SEMUA baris — kegagalan tidak boleh
  /// hilang dari senarai Cuba Semula hanya kerana bilangan besar.
  Future<List<FailedRecord>> failures({int? sessionId, int? limit}) async {
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
