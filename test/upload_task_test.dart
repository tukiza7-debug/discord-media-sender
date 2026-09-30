import 'dart:async';

import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/services/database_service.dart';
import 'package:discord_media_sender/services/upload_engine.dart';
import 'package:discord_media_sender/services/upload_task_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'upload_session_test.dart' show FakeDiscordApi;

// ------------------------------------------------------------- enjin palsu

/// Enjin palsu — merakam arahan & baris yang diterima (TESTS: arahan batal
/// & status dalam logik task, enjin dipalsukan).
class FakeEngine extends UploadEngine {
  FakeEngine() : super(api: FakeDiscordApi());

  List<MediaItem>? lastItems;
  String cannedStatus = 'completed';
  String? cannedReason;
  int cancelCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  bool busy = false;

  /// Pegang run() sehingga cancel() — untuk uji batal semasa berjalan.
  bool hold = false;
  Completer<String>? _gate;

  @override
  bool get isBusy => busy;

  @override
  String? get lastReason => cannedReason;

  @override
  UploadProgress get lastProgress => UploadProgress(
        state: EngineState.done,
        totalBatches: 1,
        currentBatch: 1,
        totalFiles: lastItems?.length ?? 0,
        successFiles: 0,
        failedFiles: 0,
        uploadedBytes: 0,
        totalBytes: 0,
        speedMBps: 0,
      );

  @override
  Future<String> run({
    required List<MediaItem> items,
    required SendConfig config,
    String? caption,
    required OnBatchFailed onBatchFailed,
    OnBatchSucceeded? onBatchSucceeded,
    OnForegroundUpdate? onForegroundUpdate,
    int maxBatchBytes = AppLimits.defaultMaxFileMB * 1024 * 1024,
  }) async {
    lastItems = items;
    busy = true;
    String status = cannedStatus;
    if (hold) {
      _gate = Completer<String>();
      status = await _gate!.future;
    }
    busy = false;
    return status;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _gate?.complete(cannedStatus);
    _gate = null;
  }

  @override
  void pause() => pauseCalls++;

  @override
  void resume() => resumeCalls++;
}

// ---------------------------------------------------------------- DB palsu

/// DB palsu dalam memori — semantik minimum yang dipakai UploadTaskCore.
class FakeTaskDb implements DatabaseService {
  int nextId = 1;
  final sessionRows = <int, Map<String, dynamic>>{};
  final files = <int, List<Map<String, dynamic>>>{};
  final failureRows = <Map<String, dynamic>>[];
  final heartbeatCalls = <int>[];
  String? finishReason;
  String? finishStatus;

  int insertSession({required int totalFiles}) {
    final id = nextId++;
    sessionRows[id] = {
      'id': id,
      'started_at': 0,
      'ended_at': 0,
      'mode': 'webhook',
      'target': 'x',
      'total_files': totalFiles,
      'success': 0,
      'failed': 0,
      'status': 'running',
    };
    files[id] = [
      for (var i = 0; i < totalFiles; i++)
        {
          'session_id': id,
          'idx': i,
          'path': '/media/file$i.jpg',
          'name': 'file$i.jpg',
          'size': 100,
          'status': 'pending',
          'error': null,
        }
    ];
    return id;
  }

  void markFile(int sessionId, int idx, String status) {
    files[sessionId]![idx]['status'] = status;
  }

  @override
  Future<SessionRecord?> runningSession() async {
    for (final s in sessionRows.values) {
      if (s['status'] == 'running') return SessionRecord.fromMap(s);
    }
    return null;
  }

  @override
  Future<List<SessionFileRecord>> pendingSessionFiles(int sessionId) async => [
        for (final f in files[sessionId] ?? const [])
          if (f['status'] == 'pending') SessionFileRecord.fromMap(f)
      ];

  @override
  Future<int> pendingFileCount(int sessionId) async =>
      (await pendingSessionFiles(sessionId)).length;

  @override
  Future<Map<String, int>> sessionFileStatusCounts(int sessionId) async {
    final counts = <String, int>{};
    for (final f in files[sessionId] ?? const []) {
      counts[f['status'] as String] = (counts[f['status'] as String] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<void> markSessionFiles(int sessionId, Iterable<String> paths,
      {required String status, String? error}) async {
    for (final f in files[sessionId] ?? const []) {
      if (paths.contains(f['path'])) {
        f['status'] = status;
        f['error'] = error;
      }
    }
  }

  @override
  Future<void> skipRemainingSessionFiles(int sessionId) async {
    for (final f in files[sessionId] ?? const []) {
      if (f['status'] == 'pending') f['status'] = 'skipped';
    }
  }

  @override
  Future<List<String>> sessionFilePaths(int sessionId) async =>
      [for (final f in files[sessionId] ?? const []) f['path'] as String];

  @override
  Future<Set<String>> runningSessionFilePaths() async => {
        for (final id in sessionRows.keys
            .where((id) => sessionRows[id]!['status'] == 'running'))
          ...await sessionFilePaths(id)
      };

  @override
  Future<void> touchHeartbeat(int sessionId) async {
    heartbeatCalls.add(sessionId);
  }

  @override
  Future<void> finishSession(int id,
      {required int success,
      required int failed,
      required String status,
      String? reason}) async {
    sessionRows[id]!['success'] = success;
    sessionRows[id]!['failed'] = failed;
    sessionRows[id]!['status'] = status;
    sessionRows[id]!['reason'] = reason;
    finishStatus = status;
    finishReason = reason;
  }

  @override
  Future<void> addFailures(List<FailedRecord> list) async {
    failureRows.addAll([for (final f in list) f.toMap()..remove('id')]);
  }

  @override
  Future<void> deleteFailuresByPaths(Iterable<String> paths) async {
    failureRows.removeWhere((r) => paths.contains(r['file_path']));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} not faked');
}

// ---------------------------------------------------------------- helper

UploadTaskCore makeCore(FakeEngine engine, FakeTaskDb db, List<Object> events) {
  return UploadTaskCore(
    engine: engine,
    db: db,
    sendEvent: events.add,
    updateNotification: (title, text) {},
    stopService: () async {},
    // Konfigurasi palsu (bukan rahsia) — storan selamat tiada platform dlm
    // persekitaran ujian.
    configLoader: () async => const SendConfig(
        mode: SendMode.webhook, webhookUrl: 'https://webhook.site/xxxx'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('arahan cancel tanpa enjin sibuk → hanya event status (2e)', () async {
    final engine = FakeEngine();
    final events = <Object>[];
    final core = makeCore(engine, FakeTaskDb(), events);

    await core.handleCommand({'cmd': 'cancel'});
    expect(engine.cancelCalls, 0); // enjin tidak sibuk → status sahaja
    expect(events.map((e) => (e as Map)['event']), contains('status'));
  });

  test('arahan cancel semasa enjin sibuk → engine.cancel dipanggil', () async {
    final engine = FakeEngine()..busy = true;
    final core = makeCore(engine, FakeTaskDb(), <Object>[]);

    await core.handleCommand({'cmd': 'cancel'});
    expect(engine.cancelCalls, 1);
  });

  test('arahan pause/resume dipeterjalkan kepada enjin', () async {
    final engine = FakeEngine()..busy = true;
    final core = makeCore(engine, FakeTaskDb(), <Object>[]);
    await core.handleCommand({'cmd': 'pause'});
    await core.handleCommand({'cmd': 'resume'});
    expect(engine.pauseCalls, 1);
    expect(engine.resumeCalls, 1);
  });

  test('arahan status → event status (tiada sesi, 2c)', () async {
    final events = <Object>[];
    final core = makeCore(FakeEngine(), FakeTaskDb(), events);
    await core.handleCommand({'cmd': 'status'});
    final e = events.first as Map;
    expect(e['event'], 'status');
    expect(e['running'], isFalse);
  });

  test('SESI TUNGGAL: id yang tidak aktif → startRejected (2e)', () async {
    final engine = FakeEngine();
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    db.insertSession(totalFiles: 1); // sesi lain 'running' (id = 1)

    await core.handleStart({'sessionId': 999999, 'maxBatchBytes': 0, 'caption': ''});
    final rejected = events
        .where((e) => (e as Map)['event'] == 'startRejected')
        .toList();
    expect(rejected, isNotEmpty);
    expect(engine.lastItems, isNull); // enjin tidak pernah dijalankan
  });

  test('MULA: enjin menerima baris PENDING sahaja (2d — resume)', () async {
    final engine = FakeEngine();
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 5);
    // 2 fail sudah dihantar sebelum proses mati (2b); 1 gagal.
    db.markFile(id, 0, 'sent');
    db.markFile(id, 1, 'sent');
    db.markFile(id, 2, 'failed');

    await core.handleStart(
        {'sessionId': id, 'maxBatchBytes': 20 * 1024 * 1024, 'caption': ''});
    await _waitForEvent(events, 'finished');

    // Baris pending sahaja (idx 3 & 4) — sent TIDAK dihantar semula.
    expect(engine.lastItems, hasLength(2));
    expect(engine.lastItems!.map((m) => m.name),
        everyElement(anyOf('file3.jpg', 'file4.jpg')));
  });

  test('TAMAT: status akhir dari BARIS (DB ialah sumber kebenaran, 2b)',
      () async {
    final engine = FakeEngine()..cannedStatus = 'completed';
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 4);
    db.markFile(id, 0, 'failed');
    db.markFile(id, 1, 'failed');

    await core.handleStart(
        {'sessionId': id, 'maxBatchBytes': 20 * 1024 * 1024, 'caption': ''});
    await _waitForEvent(events, 'finished');

    final finished =
        events.firstWhere((e) => (e as Map)['event'] == 'finished') as Map;
    // Enjin kata 'completed', tetapi baris menunjukkan 2 gagal & 0 sent.
    expect(finished['status'], 'failed');
    expect(db.finishStatus, 'failed');
    expect(db.finishReason, isNotNull); // tiada status gagal tanpa sebab
    expect(db.sessionRows[id]!['success'], 0);
    expect(db.sessionRows[id]!['failed'], 2);
  });

  test('TAMAT: partial → sebab mengandungi ralat enjin + nota resume',
      () async {
    final engine = FakeEngine()
      ..cannedStatus = 'partial'
      ..cannedReason = 'Batch 1 failed after 3 attempts. Last error: x';
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 4);
    db.markFile(id, 0, 'sent'); // dari larian sebelum gangguan
    db.markFile(id, 1, 'failed');

    await core.handleStart(
        {'sessionId': id, 'maxBatchBytes': 20 * 1024 * 1024, 'caption': ''});
    await _waitForEvent(events, 'finished');

    final finished =
        events.firstWhere((e) => (e as Map)['event'] == 'finished') as Map;
    expect(finished['status'], 'partial');
    expect(db.finishReason, contains('Batch 1 failed after 3 attempts'));
    expect(db.finishReason, contains('Resumed after the app process was interrupted'));
  });

  test('BATAL dari NOTIFIKASI → sebab teks tepat (2e)', () async {
    final engine = FakeEngine()
      ..cannedStatus = 'cancelled'
      ..hold = true;
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 3);

    await core.handleStart(
        {'sessionId': id, 'maxBatchBytes': 20 * 1024 * 1024, 'caption': 'cap'});
    await Future<void>.delayed(const Duration(milliseconds: 20)); // biar run mula
    await core.handleCancel(fromNotification: true);
    await _waitForEvent(events, 'finished');

    expect(db.finishStatus, 'cancelled');
    // 2e: teks tepat seperti spesifikasi (bukan sesi resume — tiada nota).
    expect(db.finishReason, 'Cancelled by user from the notification.');
    // Baki pending → skipped (tidak pernah hilang senyap).
    final counts = await db.sessionFileStatusCounts(id);
    expect(counts['skipped'], 3);
    expect(counts['sent'], isNull); // tiada fail dihantar
  });

  test('denyar (heartbeat) dicatat semasa sesi bermula (2d)', () async {
    final engine = FakeEngine();
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 1);
    await core.handleStart(
        {'sessionId': id, 'maxBatchBytes': 20 * 1024 * 1024, 'caption': ''});
    await _waitForEvent(events, 'finished');
    expect(db.heartbeatCalls, isNotEmpty);
  });

  test('RESTART tanpa baris pending → sesi difinalkan dari baris (2d)',
      () async {
    final engine = FakeEngine();
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 2);
    db.markFile(id, 0, 'sent');
    db.markFile(id, 1, 'sent');

    await core.handleStart({'sessionId': id, 'maxBatchBytes': 0, 'caption': ''});
    await _waitForEvent(events, 'finished');

    expect(engine.lastItems, isNull); // enjin TIDAK dijalankan
    final finished =
        events.firstWhere((e) => (e as Map)['event'] == 'finished') as Map;
    expect(finished['status'], 'completed');
    expect(db.sessionRows[id]!['success'], 2);
  });

  test('event log dari API masuk buffer + diteruskan semasa attach (2c)', () {
    final events = <Object>[];
    final core = makeCore(FakeEngine(), FakeTaskDb(), events);
    final entry = ResponseLogEntry(
      id: 'e1',
      batchNumber: 1,
      totalBatches: 1,
      fileCount: 1,
      fileNames: const ['a.jpg'],
      filePaths: const ['/a.jpg'],
      endpoint: 'webhooks/****',
      method: 'POST',
      status: LogStatus.success,
      statusCode: 200,
      reasonPhrase: 'OK',
      latencyMs: 10,
      uploadBytes: 1,
      speedMBps: 1,
      attempt: 1,
      timestamp: DateTime.now(),
    );
    core.onApiLog(entry);
    final e = events.first as Map;
    expect(e['event'], 'log');
    expect((e['entry'] as Map)['id'], 'e1');
    // Buffer dihantar semula semasa attach.
    core.sendStatus();
    final status = events.last as Map;
    expect((status['logs'] as List), hasLength(1));
  });

  test('RAHSIA: sebab tidak mengandungi URL webhook / token (2a)', () async {
    final engine = FakeEngine()
      ..cannedStatus = 'failed'
      ..cannedReason =
          'Discord rejected the upload (HTTP 403): https://discord.com/api/webhooks/123456/tokentokentokentokentoken';
    final db = FakeTaskDb();
    final events = <Object>[];
    final core = makeCore(engine, db, events);
    final id = db.insertSession(totalFiles: 1);
    await core.handleStart(
        {'sessionId': id, 'maxBatchBytes': 20 * 1024 * 1024, 'caption': ''});
    await _waitForEvent(events, 'finished');
    final reason = db.finishReason!;
    // Token & ID penuh webhook mesti ditopeng; bentuk bertopeng dibenarkan.
    expect(reason.contains('webhooks/123456'), isFalse);
    expect(reason.contains('tokentokentokentokentoken'), isFalse);
    expect(reason, isNotEmpty);
  });
}

Future<void> _waitForEvent(List<Object> events, String name) async {
  for (var i = 0; i < 300; i++) {
    if (events.any((e) => e is Map && e['event'] == name)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Event "$name" tidak diterima');
}
