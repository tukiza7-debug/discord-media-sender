import 'dart:io';

import 'package:archive/archive.dart';
import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/providers/media_providers.dart';
import 'package:discord_media_sender/screens/history/history_screen.dart';
import 'package:discord_media_sender/services/database_service.dart';
import 'package:discord_media_sender/services/discord_api.dart';
import 'package:discord_media_sender/services/media_service.dart';
import 'package:discord_media_sender/services/upload_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'upload_session_test.dart' show FakeDiscordApi;

// ------------------------------------------------------------- helpers

SendConfig _cfg() => const SendConfig(
      mode: SendMode.webhook,
      webhookUrl: 'https://discord.com/api/webhooks/1234****/xxxx****',
    );

Future<File> _tempFile(String name,
    [List<int> bytes = const [1, 2, 3, 4]]) async {
  final dir = await Directory.systemTemp.createTemp('dms_nodrop');
  return File('${dir.path}/$name').writeAsBytes(bytes);
}

MediaItem _item(File f, {int? size}) => MediaItem(
      id: 'id-${f.path}',
      path: f.path,
      name: f.path.split('/').last,
      sizeBytes: size ?? f.lengthSync(),
      type: MediaType.image,
      mimeType: 'image/png',
    );

MediaItem _missingItem(String name) => MediaItem(
      id: 'missing-$name',
      path: '/nonexistent/dir/$name',
      name: name,
      sizeBytes: 10,
      type: MediaType.image,
      mimeType: 'image/png',
    );

void _noop(List<MediaItem> b, int i, int? h, int? d, String? m) {}

/// DB tiruan untuk widget test — hanya sessions()/failures().
class FakeHistoryDb implements DatabaseService {
  FakeHistoryDb(this.sessionRows);
  final List<SessionRecord> sessionRows;

  @override
  Future<List<SessionRecord>> sessions({int limit = 500}) async => sessionRows;

  @override
  Future<List<FailedRecord>> failures({int? sessionId, int? limit}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} not faked');
}

void main() {
  // --------------------------------------------------------- 1: >5000
  test('1: lebih 5000 item diterima oleh addAll dan _validate', () async {
    final notifier = MediaListNotifier();
    final items = List.generate(
      5001,
      (i) => MediaItem(
        id: 'id-$i',
        path: '/x/f$i.png',
        name: 'f$i.png',
        sizeBytes: 1,
        type: MediaType.image,
        mimeType: 'image/png',
      ),
    );
    notifier.addAll(items);
    expect(notifier.state.length, 5001,
        reason: 'addAll tidak lagi mengehadkan 5000');

    final dir = await Directory.systemTemp.createTemp('dms_many');
    for (var i = 0; i < 5001; i++) {
      File('${dir.path}/f$i.png').writeAsBytesSync([1]);
    }
    final res = MediaService.scanFolderSync(dir.path, maxFileMB: 20);
    expect(res.items.length, 5001,
        reason: '_validate menerima melebihi 5000 fail');
    expect(res.skipped.where((s) => s.contains('file limit')), isEmpty,
        reason: 'tiada lagi mesej had fail');
    dir.deleteSync(recursive: true);
  });

  // --------------------------------------------------------- 2: format
  test('2: heic/tiff/svg dijumpai oleh scanFolderSync', () async {
    final dir = await Directory.systemTemp.createTemp('dms_fmt');
    File('${dir.path}/a.heic').writeAsBytesSync([1]);
    File('${dir.path}/b.tiff').writeAsBytesSync([1]);
    File('${dir.path}/c.svg').writeAsBytesSync([1]);
    final res = MediaService.scanFolderSync(dir.path);
    final names = res.items.map((m) => m.name).toSet();
    expect(names, {'a.heic', 'b.tiff', 'c.svg'});
    expect(res.items.firstWhere((m) => m.name == 'a.heic').mimeType,
        'image/heic');
    expect(res.items.firstWhere((m) => m.name == 'b.tiff').mimeType,
        'image/tiff');
    expect(res.items.firstWhere((m) => m.name == 'c.svg').mimeType,
        'image/svg+xml');
    dir.deleteSync(recursive: true);
  });

  // ------------------------------------- 3: fail tersembunyi vs sampah
  test("3: '.photo.jpg' TIDAK dilangkau; .thumbnails/. _x.jpg/.nomedia dilangkau",
      () async {
    final dir = await Directory.systemTemp.createTemp('dms_dot');
    File('${dir.path}/.photo.jpg').writeAsBytesSync([1]);
    File('${dir.path}/._x.jpg').writeAsBytesSync([1]);
    File('${dir.path}/.nomedia').writeAsBytesSync([1]);
    final thumbs = Directory('${dir.path}/.thumbnails')..createSync();
    File('${thumbs.path}/inside.png').writeAsBytesSync([1]);
    final camera = Directory('${dir.path}/.Camera')..createSync();
    File('${camera.path}/real.png').writeAsBytesSync([1]);

    final res = MediaService.scanFolderSync(dir.path);
    final names = res.items.map((m) => m.name).toSet();
    expect(names, contains('.photo.jpg'),
        reason: 'imej berawalan titik tidak lagi dilangkau');
    expect(names, contains('real.png'),
        reason: 'folder .Camera bukan sampah — tetap diimbas');
    expect(names, isNot(contains('inside.png')),
        reason: '.thumbnails ialah sampah yang dikenali');
    expect(names, isNot(contains('._x.jpg')),
        reason: '._* ialah sampah yang dikenali');
    expect(names, isNot(contains('.nomedia')),
        reason: '.nomedia ialah sampah yang dikenali');
    dir.deleteSync(recursive: true);
  });

  // -------------------------------------------------- 4: entri rosak ZIP
  test('4: satu entri ZIP rosak — yang lain tetap diekstrak', () async {
    final dir = await Directory.systemTemp.createTemp('dms_corrupt');
    final zipFile = File('${dir.path}/in.zip');
    final archive = Archive();
    archive.addFile(ArchiveFile('ok1.png', 4, [1, 2, 3, 4]));
    archive.addFile(ArchiveFile('rosak.png', 64, List.filled(64, 7)));
    archive.addFile(ArchiveFile('ok2.png', 4, [5, 6, 7, 8]));
    final bytes = ZipEncoder().encode(archive)!.toList();

    // Rosakkan strim deflate entri KEDUA: cari local file header ke-2,
    // lompat ke data, tulis bait tak sah (BTYPE=11 → inflate pasti gagal).
    int nthLocalHeader(List<int> b, int n) {
      var count = 0;
      for (var i = 0; i < b.length - 3; i++) {
        if (b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x03 && b[i + 3] == 0x04) {
          count++;
          if (count == n) return i;
        }
      }
      return -1;
    }

    final off = nthLocalHeader(bytes, 2);
    expect(off, greaterThan(0));
    final nameLen = bytes[off + 26] | (bytes[off + 27] << 8);
    final extraLen = bytes[off + 28] | (bytes[off + 29] << 8);
    final dataStart = off + 30 + nameLen + extraLen;
    bytes[dataStart] = 0xFF;
    bytes[dataStart + 1] = 0x00;
    bytes[dataStart + 2] = 0xFF;
    zipFile.writeAsBytesSync(bytes);

    final outDir = Directory('${dir.path}/out');
    final res =
        await MediaService.instance.extractZip(zipFile.path, destination: outDir);
    final names = res.items.map((m) => m.name).toSet();
    expect(names, containsAll(['ok1.png', 'ok2.png']),
        reason: '3e: entri lain tetap hidup walaupun satu rosak');
    expect(
        res.skipped.any((s) => s.contains('rosak.png — failed to extract')),
        isTrue,
        reason: '3e: entri rosak dilaporkan, bukan menggugurkan ZIP');
    expect(File('${outDir.path}/rosak.png').existsSync(), isFalse,
        reason: '3e: fail separa dibuang');
    outDir.deleteSync(recursive: true);
    dir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------- 8: laluan sebab
  test('8a: batal pengguna → sebab tidak kosong dgn kiraan not sent',
      () async {
    final files = <File>[
      for (var i = 0; i < 21; i++) await _tempFile('c$i.png'),
    ];
    final engine = UploadEngine(
      api: FakeDiscordApi(hangUntilCancel: true),
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final fut = engine.run(items: files.map(_item).toList(), config: _cfg(),
        caption: '', onBatchFailed: _noop);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await engine.cancel();
    final status = await fut;
    expect(status, 'cancelled');
    expect(engine.lastReason, isNotEmpty);
    expect(engine.lastReason, contains('not sent'),
        reason: '3h: fail tak dihantar dilapor dgn kiraan');
    expect(engine.lastReason, contains('21 not sent'));
  });

  test('8b: retry habis → sebab menyatakan 3 cubaan', () async {
    final f1 = await _tempFile('r1.png');
    final engine = UploadEngine(
      api: FakeDiscordApi(failTimes: 99, failWithHttp: 502),
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final status = await engine.run(items: [_item(f1)], config: _cfg(),
        caption: '', onBatchFailed: _noop);
    expect(status, 'failed');
    expect(engine.lastReason, contains('failed after 3 attempts'));
  });

  test('8c: ralat tidak-boleh-retry → sebab menyebut HTTP + terjemahan',
      () async {
    final f1 = await _tempFile('r2.png');
    final engine = UploadEngine(
      api: FakeDiscordApi(failTimes: 99, failWithHttp: 403),
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final status = await engine.run(items: [_item(f1)], config: _cfg(),
        caption: '', onBatchFailed: _noop);
    expect(status, 'failed');
    expect(engine.lastReason, contains('Discord rejected the upload'));
    expect(engine.lastReason, contains('HTTP 403'));
    expect(engine.lastReason, contains('Access denied'));
  });

  test('8d: partial → sebab dgn Most common error', () async {
    final files = <File>[
      for (var i = 0; i < 11; i++) await _tempFile('p$i.png'),
    ];
    final engine = UploadEngine(
      // 3 cubaan pertama gagal (batch 1 habis cubaan), panggilan ke-4
      // berjaya (batch 2) → partial.
      api: FakeDiscordApi(failTimes: 3),
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final status = await engine.run(items: files.map(_item).toList(),
        config: _cfg(), caption: '', onBatchFailed: _noop);
    expect(status, 'partial');
    expect(engine.lastReason, contains('Most common error'));
    // 3h: invarian — success + failed == totalFiles.
    expect(engine.lastProgress.successFiles + engine.lastProgress.failedFiles,
        engine.lastProgress.totalFiles);
  });

  test('8e: semua gagal → sebab All ... failed', () async {
    final f1 = await _tempFile('r3.png');
    final engine = UploadEngine(
      api: FakeDiscordApi(failTimes: 99, failWithHttp: 502),
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final status = await engine.run(items: [_item(f1)], config: _cfg(),
        caption: '', onBatchFailed: _noop);
    expect(status, 'failed');
    expect(engine.lastReason, startsWith('All 1 file(s) failed'));
  });

  test('8f: fail hilang/oversized disebut dgn kiraan dalam sebab', () async {
    final f1 = await _tempFile('ok.png', List.filled(4, 1));
    final engine = UploadEngine(
      api: FakeDiscordApi(),
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final status = await engine.run(
      items: [
        _item(f1, size: 4),
        _missingItem('gone1.png'),
        _missingItem('gone2.png'),
        _item(await _tempFile('big1.png'), size: 100),
        _item(await _tempFile('big2.png'), size: 100),
      ],
      config: _cfg(),
      caption: '',
      maxBatchBytes: 8, // fail 100-bait → oversized
      onBatchFailed: _noop,
    );
    expect(status, 'partial',
        reason: '1 terhantar, 4 gagal (2 hilang + 2 oversized)');
    expect(engine.lastReason, contains('2 not found on device'));
    expect(engine.lastReason, contains('2 over the size limit'));
    // 3h: fail oversized DIKIRA dalam jumlah akhir.
    expect(engine.lastProgress.successFiles + engine.lastProgress.failedFiles,
        engine.lastProgress.totalFiles);
  });

  // ------------------------------------------------- 9: rahsia & sebab
  test('9: sebab tidak pernah mengandungi URL webhook/token bot', () async {
    const secretUrl =
        'https://discord.com/api/webhooks/1234567890/SECRET_WEBHOOK_TOKEN_XYZ';
    const secretToken =
        'MNoPqRsTuVwXyZ0123456789.AbCdEf.ghIjKlMnOpQrStUvWxYz012345';
    final cfg = SendConfig(mode: SendMode.webhook, webhookUrl: secretUrl);
    final engine = UploadEngine(
      api: LeakyFakeApi(secretUrl, secretToken),
      maxRetries: 1,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final f1 = await _tempFile('sec.png');
    final status = await engine.run(items: [_item(f1)], config: cfg,
        caption: '', onBatchFailed: _noop);
    expect(status, 'failed');
    expect(engine.lastReason, isNotNull);
    expect(engine.lastReason, isNot(contains('SECRET_WEBHOOK_TOKEN_XYZ')),
        reason: 'URL webhook MESTI ditapis dari sebab');
    expect(engine.lastReason, isNot(contains(secretToken)),
        reason: 'token bot MESTI ditapis dari sebab');
    expect(engine.lastReason, contains('****'));
  });

  // ------------------------------------- 7: SessionRecord round-trip
  test('7: SessionRecord round-trip reason (termasuk null / legacy v2)',
      () {
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final withReason = SessionRecord(
      startedAt: now,
      endedAt: now,
      mode: 'webhook',
      target: '#x',
      totalFiles: 10,
      successCount: 7,
      failedCount: 3,
      status: 'partial',
      reason: '3 of 10 file(s) failed. Most common error: X.',
    );
    final back1 = SessionRecord.fromMap(withReason.toMap());
    expect(back1.reason, withReason.reason);
    expect(back1.status, 'partial');

    final noReason = SessionRecord(
      startedAt: now,
      endedAt: now,
      mode: 'bot',
      target: '#y',
      totalFiles: 1,
      successCount: 1,
      failedCount: 0,
      status: 'completed',
    );
    expect(SessionRecord.fromMap(noReason.toMap()).reason, isNull);

    // Baris DB v2 warisan (tiada kolum reason) — tidak crash, normalisasi
    // status lama kekal.
    final legacy = SessionRecord.fromMap({
      'id': 9,
      'started_at': now.millisecondsSinceEpoch,
      'ended_at': now.millisecondsSinceEpoch,
      'mode': 'webhook',
      'target': '#z',
      'total_files': 2,
      'success': 1,
      'failed': 1,
      'status': 'separa',
    });
    expect(legacy.reason, isNull);
    expect(legacy.status, 'partial');
  });

  // ---------------------------------------------------- 10: widget test
  testWidgets('10: butiran sesi tunjuk sebab batal + teks tiada sebab',
      (tester) async {
    // Permukaan lebih luas: font ujian (Ahem) lebih lebar daripada font
    // sebenar — kad sesi lama (tidak diubah) melimpah pada 800px lalai.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final originalDb = DatabaseService.instance;
    DatabaseService.instance = FakeHistoryDb([
      SessionRecord(
        id: 1,
        startedAt: DateTime(2026, 9, 30, 10),
        endedAt: DateTime(2026, 9, 30, 10, 5),
        mode: 'webhook',
        target: 'Cancelled Session',
        totalFiles: 10,
        successCount: 5,
        failedCount: 0,
        status: 'cancelled',
        reason: 'Cancelled by user at batch 2 of 2. 5 file(s) sent, 5 not sent.',
      ),
    ]);
    addTearDown(() => DatabaseService.instance = originalDb);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(),
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelled Session'));
    await tester.pumpAndSettle();

    expect(find.text('REASON'), findsOneWidget);
    expect(find.textContaining('Cancelled by user at batch 2 of 2'),
        findsOneWidget);
    expect(find.textContaining('Not sent: 5'), findsOneWidget,
        reason: 'baris kiraan: sent/failed/not-sent');

    // Sesi warisan tanpa sebab (null) — teks khusus dipapar.
    DatabaseService.instance = FakeHistoryDb([
      SessionRecord(
        id: 2,
        startedAt: DateTime(2026, 9, 30, 11),
        endedAt: DateTime(2026, 9, 30, 11, 5),
        mode: 'webhook',
        target: 'Old Failed Session',
        totalFiles: 4,
        successCount: 0,
        failedCount: 4,
        status: 'failed',
      ),
    ]);
    // KeyedSubtree berunik: paksa remount penuh (initState → load() semula)
    // — tanpa itu, elemen lama diguna semula dan senarai tidak diMuat semula.
    await tester.pumpWidget(KeyedSubtree(
      key: UniqueKey(),
      child: UncontrolledProviderScope(
        container: ProviderContainer(),
        child: const MaterialApp(home: HistoryScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Failed Session'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'No reason was recorded for this session (created before this update).'),
        findsOneWidget);
  });
}

/// API palsu yang melontar ralat MENGANDUNGI rahsia — membuktikan getter
/// lastReason menapis URL webhook & token bot.
class LeakyFakeApi extends DiscordApi {
  LeakyFakeApi(this.url, this.token);
  final String url;
  final String token;

  @override
  Future<BatchOutcome> sendBatch({
    required SendConfig config,
    required List<MediaItem> files,
    String? caption,
    CancelToken? cancelToken,
    required int batchNumber,
    required int totalBatches,
    required int attempt,
    void Function(int sent, int total)? onProgress,
    bool Function()? isCancelled,
    void Function()? onRateLimitWaitTick,
  }) async {
    throw Exception('POST $url failed with token $token');
  }
}
