import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:discord_media_sender/core/error_translator.dart';
import 'package:discord_media_sender/core/secure_store.dart';
import 'package:discord_media_sender/core/validators.dart';
import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/providers/config_providers.dart';
import 'package:discord_media_sender/providers/media_providers.dart';
import 'package:discord_media_sender/providers/upload_providers.dart';
import 'package:discord_media_sender/screens/send/send_screen.dart';
import 'package:discord_media_sender/services/database_service.dart';
import 'package:discord_media_sender/services/discord_api.dart';
import 'package:discord_media_sender/services/media_service.dart';
import 'package:discord_media_sender/services/upload_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'upload_session_test.dart' show FakeDiscordApi;

// ----------------------------------------------------------------- fake DB

/// B03/B04/B05: DB tiruan dalam memori — semantik UPSERT-ikut-path sama
/// seperti DatabaseService.addFailures yang sebenar.
class FakeDb implements DatabaseService {
  int sessionsCreated = 0;
  int finishCalls = 0;
  final Map<String, Map<String, dynamic>> failuresByPath = {};
  final Set<String> deletedPaths = {};
  String? lastFinishStatus;
  String? lastFinishReason;

  @override
  Future<int> createSession(SessionRecord s) async => ++sessionsCreated;

  @override
  Future<void> finishSession(int id,
      {required int success,
      required int failed,
      required String status,
      String? reason}) async {
    finishCalls++;
    lastFinishStatus = status;
    lastFinishReason = reason;
  }

  @override
  Future<void> addFailures(List<FailedRecord> list) async {
    for (final f in list) {
      failuresByPath[f.filePath] = f.toMap()..remove('id');
    }
  }

  @override
  Future<void> deleteFailuresByPaths(Iterable<String> paths) async {
    for (final p in paths) {
      if (failuresByPath.remove(p) != null) deletedPaths.add(p);
    }
  }

  @override
  Future<List<FailedRecord>> failures({int? sessionId, int? limit}) async =>
      [for (final m in failuresByPath.values) FailedRecord.fromMap(m)];

  @override
  Future<void> clearAll() async {
    failuresByPath.clear();
    sessionsCreated = 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} not faked');
}

// ------------------------------------------------------- secure storage

class ThrowingStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('secure storage corrupted');
}

/// Platform storage in-memory (dari pakej, semula diberi nama pendek).
TestFlutterSecureStoragePlatform memoryStorage(Map<String, String> data) =>
    TestFlutterSecureStoragePlatform(data);

// ----------------------------------------------------------- helper media

Future<File> _tempFile(String name, [int size = 10]) async {
  final dir = await Directory.systemTemp.createTemp('dms_audit');
  return File('${dir.path}/$name').writeAsBytes(List.filled(size, 1));
}

MediaItem _item(File f) => MediaItem(
      id: 'id-${f.path}',
      path: f.path,
      name: f.path.split('/').last,
      sizeBytes: f.lengthSync(),
      type: MediaType.image,
      mimeType: 'image/png',
    );

SendConfig _cfg() => const SendConfig(
      mode: SendMode.webhook,
      webhookUrl: 'https://discord.com/api/webhooks/1234****/xxxx****',
    );

/// Container dengan engine & DB diganti.
(ProviderContainer, FakeDiscordApi, FakeDb) _makeContainer(
    {FakeDiscordApi? api}) {
  final fakeApi = api ?? FakeDiscordApi();
  final db = FakeDb();
  final originalDb = DatabaseService.instance;
  DatabaseService.instance = db;
  final container = ProviderContainer(overrides: [
    uploadControllerProvider.overrideWith(
        (ref) => UploadController(ref, engine: UploadEngine(api: fakeApi))),
  ]);
  addTearDown(() {
    container.dispose();
    DatabaseService.instance = originalDb;
  });
  return (container, fakeApi, db);
}

void main() {
  // ------------------------------------------------------------- B07
  test('B07: kod Discord 0 diabaikan — penerangan HTTP (Invalid token) digunakan',
      () {
    final expl = ErrorTranslator.explain(statusCode: 401, discordCode: 0);
    expect(expl.title, 'Invalid token');
    // Tiada literal ".title" dalam mana-mana penerangan (bug interpolasi).
    expect(expl.title.contains('.title'), isFalse);
    expect(expl.detail.contains('.title'), isFalse);
  });

  test('B07: peta baharu — 10015 / 50027 / 50035 diterjemah dgn cadangan',
      () {
    final e1 = ErrorTranslator.explain(discordCode: 10015);
    expect(e1.title, 'Unknown webhook');
    expect(e1.suggestions, isNotEmpty);
    final e2 = ErrorTranslator.explain(discordCode: 50027);
    expect(e2.title, 'Invalid webhook token');
    final e3 = ErrorTranslator.explain(discordCode: 50035);
    expect(e3.title, 'Invalid form body');
  });

  // ------------------------------------------------------------- B11
  test('B11: URL webhook tidak sah menyekat configValid', () {
    const bad = SendConfig(
        mode: SendMode.webhook, webhookUrl: 'https://example.com/hook');
    expect(configValid(bad), isFalse);
    const good = SendConfig(
        mode: SendMode.webhook,
        webhookUrl: 'https://discord.com/api/webhooks/123456789012345678/AbCdEfGh1234567890');
    expect(configValid(good), isTrue);
    const badBot = SendConfig(mode: SendMode.bot, botToken: 'short', channelId: '123');
    expect(configValid(badBot), isFalse);
  });

  testWidgets('B11: ketikan pantas kekal NILAI AKHIR (debounce + giliran)',
      (tester) async {
    final data = <String, String>{};
    FlutterSecureStoragePlatform.instance = memoryStorage(data);
    addTearDown(
        () => FlutterSecureStoragePlatform.instance = ThrowingStoragePlatform());

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(configProvider.notifier);
    await notifier.load();

    notifier.setWebhookUrl('https://discord.com/api/webhooks/1/a');
    notifier.setWebhookUrl('https://discord.com/api/webhooks/2/b');
    notifier.setWebhookUrl('https://discord.com/api/webhooks/3/c');
    await notifier.flush();

    expect(data['cfg_webhook_url'],
        'https://discord.com/api/webhooks/3/c',
        reason: 'nilai akhir yang mesti kekal — bukan nilai pertengahan');
  });

  testWidgets('B11: suntingan manual Channel ID membersihkan channelName',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(configProvider.notifier);

    notifier.setChannel(id: '111', name: 'general');
    expect(container.read(configProvider).channelName, 'general');

    notifier.setChannel(id: '222'); // manual — tanpa name
    expect(container.read(configProvider).channelName, isEmpty,
        reason: 'channelName lama tidak lagi melekat (bug B11)');

    // Batalkan timer debounce supaya testWidgets tidak gagal
    // 'Timer still pending'.
    await notifier.flush();
  });

  // ------------------------------------------------------------- B06
  test('B06: storan selamat yang melempar → app hidup dengan nilai lalai',
      () async {
    FlutterSecureStoragePlatform.instance = ThrowingStoragePlatform();
    addTearDown(
        () => FlutterSecureStoragePlatform.instance = ThrowingStoragePlatform());

    final cfg = await SecureStore.loadConfigSafe();
    expect(cfg['mode'], 'webhook'); // lalai
    expect(cfg['webhookUrl'], '');

    final settings = await SecureStore.loadSettingsSafe();
    expect(settings.themeMode, 'dark');
    expect(settings.maxFileMB, 20);
  });

  // ------------------------------------------------------------- B01
  test('B01: 429 dgn body retry_after=1.5s + header 2s → tunggu ~2000ms',
      () async {
    final adapter = _MockAdapter();
    final api = DiscordApi()..debugAttachAdapter(adapter);
    final logs = <ResponseLogEntry>[];
    api.onLog = logs.add;

    final sw = Stopwatch()..start();
    final outcome = await api.sendBatch(
      config: _cfg(),
      files: const [],
      caption: '',
      batchNumber: 1,
      totalBatches: 1,
      attempt: 1,
    );
    sw.stop();

    expect(outcome.success, isTrue,
        reason: 'selepas menghormati 429, POST kedua berjaya');
    expect(adapter.posts, 2);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(1900),
        reason: 'header Retry-After: 2 → 2000 ms (bukan 2 ms!)');
    expect(sw.elapsedMilliseconds, lessThan(4000));
    final rateEntry = logs.firstWhere((e) => e.status == LogStatus.rateLimited);
    expect(rateEntry.retryAfterMs, 2000,
        reason: 'kad countdown mesti memaparkan tunggu sebenar');
  });

  test('B01: batal semasa menunggu 429 → keluar segera, TIADA POST kedua',
      () async {
    final adapter = _MockAdapter();
    final api = DiscordApi()..debugAttachAdapter(adapter);

    final token = CancelToken();
    Timer(const Duration(milliseconds: 250), () => token.cancel());

    final sw = Stopwatch()..start();
    final outcome = await api.sendBatch(
      config: _cfg(),
      files: const [],
      caption: '',
      cancelToken: token,
      batchNumber: 1,
      totalBatches: 1,
      attempt: 1,
    );
    sw.stop();

    expect(outcome.cancelled, isTrue);
    expect(adapter.posts, 1,
        reason: 'tiada POST pendua selepas batal semasa tunggu');
    expect(sw.elapsedMilliseconds, lessThan(1500),
        reason: 'keluar segera dari tunggu 2s');
  });

  test('B18: payload_json mengandungi allowed_mentions parse=[]', () async {
    final adapter = _MockAdapter();
    final api = DiscordApi()..debugAttachAdapter(adapter);

    await api.sendBatch(
      config: _cfg(),
      files: const [],
      caption: 'hello @everyone',
      batchNumber: 1,
      totalBatches: 1,
      attempt: 1,
    );

    expect(adapter.payloadJson, isNotNull);
    final payload = jsonDecode(adapter.payloadJson!) as Map<String, dynamic>;
    expect(payload['allowed_mentions'], {'parse': <String>[]},
        reason: 'kapsyen dengan @everyone TIDAK boleh mass-mention');
  });

  // ------------------------------------------------------------- B03
  test('B03: start() dua kali pantas → SATU sesi, SATU run, tanpa kerosakan',
      () async {
    final f1 = await _tempFile('race.png');
    final (container, api, db) = _makeContainer(
        api: FakeDiscordApi(hangUntilCancel: true));
    container.read(mediaListProvider.notifier).addAll([_item(f1)]);
    final controller = container.read(uploadControllerProvider.notifier);

    // Dua panggilan TANPA menunggu yang pertama selesai.
    final fut1 = controller.start(items: container.read(mediaListProvider),
        config: _cfg(), caption: '');
    final fut2 = controller.start(items: container.read(mediaListProvider),
        config: _cfg(), caption: '');
    final r2 = await fut2;

    expect(r2.kind, SendResultKind.rejected);

    // Beri masa sesi pertama sampai ke createSession (beberapa await
    // platform di hadapannya — semua dilindungi try/catch).
    for (var i = 0; i < 100 && db.sessionsCreated == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(db.sessionsCreated, 1,
        reason: 'hanya SATU baris sesi dicipta');
    expect(api.calls, 1,
        reason: 'tepat SATU run enjin (batch tergantung) — bukan dua');

    // Selesaikan sesi pertama.
    await container.read(uploadControllerProvider.notifier).engine.cancel();
    final r1 = await fut1;
    expect(r1.kind, SendResultKind.cancelled);
    expect(db.finishCalls, 1,
        reason: "panggilan kedua tidak memanggil finishSession('already-running')");
  });

  // ------------------------------------------------------------- B04
  test('B04: retry BERJAYA membuang baris gagal lama', () async {
    final f1 = await _tempFile('retry-ok.png');
    final (container, api, db) = _makeContainer();
    db.failuresByPath[f1.path] = {
      'file_name': 'retry-ok.png',
      'file_path': f1.path,
      'size_bytes': 10,
      'batch_index': 1,
      'error_message': 'old failure',
      'created_at': 0,
    };
    container.read(mediaListProvider.notifier).addAll([_item(f1)]);
    final controller = container.read(uploadControllerProvider.notifier);

    final result = await controller.start(
        items: container.read(mediaListProvider),
        config: _cfg(),
        caption: '');

    expect(result.kind, SendResultKind.success);
    expect(db.deletedPaths, contains(f1.path));
    expect(db.failuresByPath, isEmpty,
        reason: 'baris gagal lama dibuang selepas berjaya');
    expect(api.calls, 1);
  });

  test('B04: retry GAGAL semula → TEPAT SATU baris (tiada pendua)', () async {
    final f1 = await _tempFile('retry-fail.png');
    final (container, api, db) = _makeContainer(
        api: FakeDiscordApi(failTimes: 99, failWithHttp: 502));
    db.failuresByPath[f1.path] = {
      'file_name': 'retry-fail.png',
      'file_path': f1.path,
      'size_bytes': 10,
      'batch_index': 0,
      'error_message': 'old failure',
      'created_at': 0,
    };
    container.read(mediaListProvider.notifier).addAll([_item(f1)]);
    final controller = container.read(uploadControllerProvider.notifier);

    final result = await controller.start(
        items: container.read(mediaListProvider),
        config: _cfg(),
        caption: '');

    expect(result.kind, SendResultKind.failed);
    expect(db.failuresByPath.keys, [f1.path],
        reason: 'gagal semula mengemas kini baris lama — bukan tambah pendua');
  });

  // ------------------------------------------------------------- B05
  test('B05: selepas selesai, tiada fail ready (semua sent) + badge data',
      () async {
    final f1 = await _tempFile('s1.png');
    final f2 = await _tempFile('s2.png');
    final (container, _, db2) = _makeContainer();
    container
        .read(mediaListProvider.notifier)
        .addAll([_item(f1), _item(f2)]);
    final controller = container.read(uploadControllerProvider.notifier);

    await controller.start(
        items: container.read(mediaListProvider),
        config: _cfg(),
        caption: '');

    final items = container.read(mediaListProvider);
    expect(items.where((m) => m.status.canSend), isEmpty,
        reason: 'sedia kira = 0 selepas selesai — tiada hantar berganda');
    expect(items.every((m) => m.status == MediaStatus.sent), isTrue);
  });

  test('B05: selepas batal, baki item cancelled DAN boleh dihantar semula',
      () async {
    final f1 = await _tempFile('c1.png');
    final (container, _, db2) =
        _makeContainer(api: FakeDiscordApi(hangUntilCancel: true));
    container.read(mediaListProvider.notifier).addAll([_item(f1)]);
    final controller = container.read(uploadControllerProvider.notifier);

    final fut = controller.start(
        items: container.read(mediaListProvider),
        config: _cfg(),
        caption: '');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await controller.engine.cancel();
    await fut;

    final items = container.read(mediaListProvider);
    expect(items.single.status, MediaStatus.cancelled);
    expect(items.single.status.canSend, isTrue,
        reason: 'item cancelled boleh dihantar semula (Send remaining)');
  });

  // ------------------------------------------------------------- B12
  test('B12: onLog ditetapkan semasa provider dicipta (bukan semasa start)',
      () {
    final (container, _, db2) = _makeContainer();
    container.read(uploadControllerProvider);
    expect(DiscordApi.instance.onLog, isNotNull,
        reason: 'log uji sambungan tidak lagi hilang sebelum hantaran pertama');
  });

  // ------------------------------------------------------------- B10
  test("B10: ZIP — nama berulang hidup; entri '..' diterima guna nama asas",
      () async {
    final dir = await Directory.systemTemp.createTemp('dms_zip');
    final zipFile = File('${dir.path}/in.zip');
    final archive = Archive();
    archive.addFile(ArchiveFile('a/IMG.png', 4, [1, 2, 3, 4]));
    archive.addFile(ArchiveFile('b/IMG.png', 4, [5, 6, 7, 8]));
    // 3d: '..' TIDAK lagi menolak entri — output rata guna nama asas.
    archive.addFile(ArchiveFile('../evil.png', 4, [9, 9, 9, 9]));
    archive.addFile(ArchiveFile('sub/../../deep.png', 4, [8, 8, 8, 8]));
    archive.addFile(ArchiveFile('.DS_Store', 2, [0, 0]));
    archive.addFile(ArchiveFile('notes.txt', 2, [0x61, 0x62]));
    zipFile.writeAsBytesSync(ZipEncoder().encode(archive)!);

    final outDir = Directory('${dir.path}/out');
    final res = await MediaService.instance
        .extractZip(zipFile.path, destination: outDir);

    final names = res.items.map((m) => m.name).toSet();
    expect(names, containsAll(['IMG.png', 'IMG (1).png']),
        reason: 'dedup deterministik — kedua-dua basename hidup');
    expect(names, containsAll(['evil.png', 'deep.png']),
        reason: "3d: entri '..' diterima rata guna nama asas sahaja");
    // Tiada subdirektori dicipta — output sentiasa rata.
    expect(outDir.listSync().whereType<Directory>(), isEmpty);
    // .DS_Store / notes.txt tidak diekstrak; dirumuskan dgn satu baris.
    expect(res.skipped.any((s) => s.contains('2 file(s) ignored')) ||
        res.skipped.any((s) => s.contains('ignored (unsupported type)')),
        isTrue,
        reason: '3b: fail tidak disokong dirumuskan, bukan senyap');
    expect(outDir.listSync().length, 4,
        reason: '4 media diekstrak; notes.txt/.DS_Store tidak');

    outDir.deleteSync(recursive: true);
    dir.deleteSync(recursive: true);
  });

  // ------------------------------------------------------------- B13
  testWidgets('B13: kapsyen kekal selepas layout dibina semula (putaran)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget harness({required bool wide}) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: wide
                  ? Row(children: const [Expanded(child: CaptionField())])
                  : Column(children: const [CaptionField()]),
            ),
          ),
        );

    await tester.pumpWidget(harness(wide: false));
    await tester.enterText(find.byType(TextField), 'hello caption');
    expect(container.read(captionProvider), 'hello caption');

    // "Putaran" — struktur parent berubah → CaptionField di-mount semula.
    await tester.pumpWidget(harness(wide: true));
    expect(find.text('hello caption'), findsOneWidget,
        reason: 'teks kekal kerana controller diselaraskan dari provider');
  });

  test('B02: timeout percubaan diskalakan ikut saiz batch', () {
    // 15 minit = lantai untuk batch kecil.
    expect(UploadEngine.attemptTimeoutFor(1 * 1024 * 1024).inMinutes, 15);
    // 40 MB @ 200 KB/s = ~205 s < 15 min → masih lantai.
    expect(UploadEngine.attemptTimeoutFor(40 * 1024 * 1024).inMinutes, 15);
    // 500 MB @ 200 KB/s = 2500 s ≈ 41 min → diskalakan.
    expect(
        UploadEngine.attemptTimeoutFor(500 * 1024 * 1024).inMinutes, greaterThan(40));
  });
}

/// Adapter Dio tiruan: 429 sekali (retry_after 1.5s + header 2s), kemudian 200.
class _MockAdapter implements HttpClientAdapter {
  int posts = 0;
  String? payloadJson;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    posts++;
    // B18: baca payload_json daripada FormData (options.data) — paling
    // boleh dipercayai; fallback: badan multipart dari requestStream.
    try {
      final d = options.data;
      if (d is FormData) {
        for (final e in d.fields) {
          if (e.key == 'payload_json') payloadJson = e.value;
        }
      }
      if (payloadJson == null && requestStream != null) {
        final bb = BytesBuilder();
        await for (final chunk in requestStream) {
          bb.add(chunk);
        }
        final body = utf8.decode(bb.toBytes(), allowMalformed: true);
        final m = RegExp(r'name="payload_json"\r?\n\r?\n(\{.*?\})', dotAll: true)
            .firstMatch(body);
        payloadJson = m?.group(1);
      }
    } catch (_) {}

    if (posts == 1) {
      return ResponseBody.fromString(
        jsonEncode({'retry_after': 1.5}),
        429,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'retry-after': ['2'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
