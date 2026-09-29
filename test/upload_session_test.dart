import 'dart:io';

import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/providers/upload_providers.dart';
import 'package:discord_media_sender/services/discord_api.dart';
import 'package:discord_media_sender/services/upload_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// API Discord palsu — boleh dikonfigurasi untuk simulasi pelbagai keadaan.
class FakeDiscordApi extends DiscordApi {
  FakeDiscordApi({
    this.hangUntilCancel = false,
    this.throwError = false,
    this.failTimes = 0,
    this.failWithHttp,
    this.failWithDiscord,
    this.delay = Duration.zero,
  });

  /// Simulasi muat naik tergantung — hanya selesai bila token dibatalkan.
  final bool hangUntilCancel;
  final bool throwError;

  /// N panggilan pertama gagal (outcome gagal biasa), selepas itu berjaya —
  /// untuk menguji auto-retry 3 cubaan.
  final int failTimes;

  /// B02: kod HTTP untuk kegagalan tiruan (cth. 413 — gagal pantas).
  final int? failWithHttp;
  final int? failWithDiscord;
  final Duration delay;
  int calls = 0;
  List<CancelToken?> seenTokens = [];

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
    calls++;
    seenTokens.add(cancelToken);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throwError) throw Exception('disk exploded');
    if (calls <= failTimes) {
      return BatchOutcome(
        success: false,
        httpCode: failWithHttp ?? 502,
        discordCode: failWithDiscord,
        errorMessage: 'Server exploded',
      );
    }
    if (hangUntilCancel) {
      onProgress?.call(10, 100);
      await cancelToken?.whenCancel;
      return const BatchOutcome(success: false, cancelled: true);
    }
    onProgress?.call(50, 100);
    onProgress?.call(100, 100);
    return const BatchOutcome(success: true, httpCode: 200);
  }
}

SendConfig _cfg() => const SendConfig(
      mode: SendMode.webhook,
      webhookUrl: 'https://discord.com/api/webhooks/1234****/xxxx****',
    );

Future<File> _tempFile(String name) async {
  final dir = await Directory.systemTemp.createTemp('dms_test');
  return File('${dir.path}/$name').writeAsBytes(List.filled(10, 1));
}

MediaItem _item(File f) => MediaItem(
      id: 'id-${f.path}',
      path: f.path,
      name: f.path.split('/').last,
      sizeBytes: 10,
      type: MediaType.image,
      mimeType: 'image/png',
    );

MediaItem _missingItem() => const MediaItem(
      id: 'missing',
      path: '/nonexistent/dir/nope.png',
      name: 'nope.png',
      sizeBytes: 10,
      type: MediaType.image,
      mimeType: 'image/png',
    );

void _noopBatchFailed(List<MediaItem> b, int i, int? h, int? d, String? m) {}

void main() {
  test('progres dipancar dengan jumlah sebenar — TIADA lagi 0/0', () async {
    final f1 = await _tempFile('a.png');
    final f2 = await _tempFile('b.png');
    final api = FakeDiscordApi(delay: const Duration(milliseconds: 120));
    final engine = UploadEngine(
      api: api,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final events = <UploadProgress>[];
    final sub = engine.progressStream.listen(events.add);

    final fut = engine.run(
      items: [_item(f1), _item(f2)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    // Peristiwa awal tiba sejurus selepas run() mula — jumlah mesti > 0.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(events, isNotEmpty, reason: 'enjin mesti memancar progres awal');
    expect(events.first.totalFiles, 2);
    expect(events.first.totalBatches, 1);

    final status = await fut;
    sub.cancel();
    expect(status, 'completed');
    expect(engine.lastProgress.successFiles, 2);
    expect(engine.lastProgress.totalFiles, 2);
  });

  test('jambatan controller: state UI hidup semasa hantar (bukan 0/0)',
      () async {
    final f1 = await _tempFile('c.png');
    final f2 = await _tempFile('d.png');
    final api = FakeDiscordApi(delay: const Duration(milliseconds: 150));
    final engine = UploadEngine(
      api: api,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );
    final container = ProviderContainer(overrides: [
      uploadControllerProvider
          .overrideWith((ref) => UploadController(ref, engine: engine)),
    ]);
    addTearDown(container.dispose);
    final controller = container.read(uploadControllerProvider.notifier);

    final fut = engine.run(
      items: [_item(f1), _item(f2)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    // PUNCA BUG LAMA: state controller kekal sifar sehingga sesi tamat.
    expect(controller.state.isRunning, isTrue);
    expect(controller.state.progress.totalFiles, 2,
        reason: 'state UI mesti menunjukkan jumlah fail sebenar semasa hantar');
    expect(controller.state.progress.totalBatches, 1);

    await fut;
    // Penghantaran peristiwa broadcast ialah asinkron — beri peluang
    // microtask terakhir (peristiwa 'done') sampai ke jambatan.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.state.isRunning, isFalse);
    expect(controller.state.state, EngineState.done);
    expect(controller.state.progress.successFiles, 2);
  });

  test('batal semasa hantar → status cancelled & enjin tamat bersih',
      () async {
    final f1 = await _tempFile('e.png');
    final api = FakeDiscordApi(hangUntilCancel: true);
    final engine = UploadEngine(
      api: api,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final fut = engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.isBusy, isTrue);
    await engine.cancel();
    final status = await fut;

    expect(status, 'cancelled');
    expect(engine.isBusy, isFalse);
    expect(engine.lastProgress.state, EngineState.cancelled);
  });

  test('pengawal masa: percubaan gantung gagal → status failed, tiada zombi',
      () async {
    final f1 = await _tempFile('f.png');
    final api = FakeDiscordApi(hangUntilCancel: true);
    final engine = UploadEngine(
      api: api,
      attemptTimeout: const Duration(milliseconds: 120),
      stallTimeout: const Duration(milliseconds: 300),
      maxRetries: 2,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    // 2 percubaan (maxRetries=2), setiap satu dimatikan pengawal masa,
    // seterusnya batch gagal → sesi 'failed' — BUKAN tergantung selamanya.
    expect(status, 'failed');
    expect(api.calls, 2);
    expect(engine.isBusy, isFalse);
  });

  test('muat naik tersadai (tiada bait) dikesan pengawal stall', () async {
    final f1 = await _tempFile('g.png');
    final api = FakeDiscordApi(hangUntilCancel: true);
    final engine = UploadEngine(
      api: api,
      attemptTimeout: const Duration(minutes: 5),
      stallTimeout: const Duration(milliseconds: 100),
      maxRetries: 1,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    expect(status, 'failed');
    expect(engine.isBusy, isFalse);
  });

  test('fail hilang dilaporkan gagal — hantaran tidak tergantung', () async {
    final f1 = await _tempFile('h.png');
    final api = FakeDiscordApi();
    final engine = UploadEngine(
      api: api,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final failedBatches = <(List<MediaItem>, String?)>[];
    final status = await engine.run(
      items: [_item(f1), _missingItem()],
      config: _cfg(),
      caption: '',
      onBatchFailed: (b, i, h, d, m) => failedBatches.add((b, m)),
    );

    expect(status, 'partial'); // 1 berjaya, 1 hilang
    expect(failedBatches, hasLength(1));
    expect(failedBatches.single.$1.single.path, '/nonexistent/dir/nope.png');
    expect(failedBatches.single.$2, 'File not found on device');
    expect(engine.lastProgress.failedFiles, 1);
    expect(engine.lastProgress.successFiles, 1);
  });

  test('semua fail hilang → failed, tiada panggilan API', () async {
    final api = FakeDiscordApi();
    final engine = UploadEngine(
      api: api,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final status = await engine.run(
      items: [_missingItem()],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    expect(status, 'failed');
    expect(api.calls, 0);
    expect(engine.isBusy, isFalse);
  });

  test('ralat tidak dijangka → kegagalan batch dilaporkan (run tidak melempar)',
      () async {
    final f1 = await _tempFile('i.png');
    final api = FakeDiscordApi(throwError: true);
    final engine = UploadEngine(
      api: api,
      maxRetries: 1,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final failedBatches = <(List<MediaItem>, String?)>[];
    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: (b, i, h, d, m) => failedBatches.add((b, m)),
    );

    expect(status, 'failed');
    expect(engine.isBusy, isFalse);
    // BAHARU: pengecualian API menjadi kegagalan batch biasa — dilaporkan
    // supaya rekod Failed ditulis (dulu: senyap, Failed kekal kosong).
    expect(failedBatches, hasLength(1));
    expect(failedBatches.single.$2, contains('disk exploded'));
    expect(engine.lastProgress.failedFiles, 1);
  });

  test('auto-retry: gagal 2 kali kemudian berjaya → completed (3 cubaan)',
      () async {
    final f1 = await _tempFile('j.png');
    final api = FakeDiscordApi(failTimes: 2);
    final engine = UploadEngine(
      api: api,
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    expect(status, 'completed');
    expect(api.calls, 3, reason: 'mesti 3 cubaan automatik');
    expect(engine.lastProgress.successFiles, 1);
    expect(engine.lastProgress.failedFiles, 0);
  });

  test('auto-retry habis: API sentiasa gagal → tepat 3 cubaan, batch dilapor',
      () async {
    final f1 = await _tempFile('k.png');
    final api = FakeDiscordApi(failTimes: 99);
    final engine = UploadEngine(
      api: api,
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final failedBatches = <(List<MediaItem>, String?)>[];
    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: (b, i, h, d, m) => failedBatches.add((b, m)),
    );

    expect(status, 'failed');
    expect(api.calls, 3, reason: 'tepat 3 cubaan automatik, tidak kurang');
    expect(failedBatches, hasLength(1));
    expect(failedBatches.single.$2, 'Server exploded');
    expect(engine.lastProgress.failedFiles, 1);
  });

  test('API melontar pengecualian → retry tetap berjalan (regresi v1.0.5)',
      () async {
    final f1 = await _tempFile('l.png');
    final api = FakeDiscordApi(throwError: true);
    final engine = UploadEngine(
      api: api,
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final failedBatches = <(List<MediaItem>, String?)>[];
    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: (b, i, h, d, m) => failedBatches.add((b, m)),
    );

    // PUNCA BUG LAMA: pengecualian keluar dari loop retry → hanya 1 cubaan,
    // onBatchFailed tidak dipanggil (Failed kekal kosong).
    expect(api.calls, 3, reason: 'retry mesti terus walaupun API melontar');
    expect(status, 'failed');
    expect(failedBatches, hasLength(1));
    expect(engine.lastProgress.failedFiles, 1);
  });

  test('chunkItems mengikut saiz kelompok', () {
    final out = UploadEngine.chunkItems(List<int>.generate(25, (i) => i), 10);
    expect(out.map((e) => e.length).toList(), [10, 10, 5]);
    expect(UploadEngine.chunkItems(const <int>[], 10), isEmpty);
  });

  test('B02: 413 TIDAK dicuba semula — tepat 1 cubaan, gagal pantas',
      () async {
    final f1 = await _tempFile('m.png');
    final api = FakeDiscordApi(failTimes: 99, failWithHttp: 413);
    final engine = UploadEngine(
      api: api,
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final failedBatches = <(List<MediaItem>, int?)>[];
    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: (b, i, h, d, m) => failedBatches.add((b, h)),
    );

    expect(status, 'failed');
    expect(api.calls, 1, reason: '413 kekal — dilarang dicuba semula');
    expect(failedBatches, hasLength(1));
    expect(failedBatches.single.$2, 413);
  });

  test('B02: 5xx dicuba semula sehingga maxRetries (3 cubaan)', () async {
    final f1 = await _tempFile('n.png');
    final api = FakeDiscordApi(failTimes: 99, failWithHttp: 502);
    final engine = UploadEngine(
      api: api,
      maxRetries: 3,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final status = await engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    expect(status, 'failed');
    expect(api.calls, 3, reason: '5xx sementara — penuh 3 cubaan');
  });

  test('B02: chunkByCountAndBytes — ikut kiraan DAN jumlah bait', () {
    MediaItem mk(int mb) => MediaItem(
          id: 'x$mb',
          path: '/tmp/x$mb.png',
          name: 'x$mb.png',
          sizeBytes: mb * 1000 * 1000,
          type: MediaType.image,
          mimeType: 'image/png',
        );

    final items = [mk(5), mk(5), mk(5), mk(5)]; // 4 x 5 MB
    final (batches, rejected) = UploadEngine.chunkByCountAndBytes(
        items, 10, 10 * 1000 * 1000); // had 10 MB/batch
    // 2 fail 5MB = 10MB (tepat had, masuk); jadi [5,5], [5,5].
    expect(batches.map((b) => b.length).toList(), [2, 2]);
    expect(rejected, isEmpty);

    // Fail tunggal melebihi had → ditolak, tidak pernah dihantar.
    final big = [mk(5), mk(50)];
    final (b2, rej2) =
        UploadEngine.chunkByCountAndBytes(big, 10, 20 * 1000 * 1000);
    expect(b2.single.length, 1);
    expect(rej2.single.sizeBytes, 50 * 1000 * 1000);
  });

  test('B09: jeda semasa batch — status TIDAK kembali running sebelum resume',
      () async {
    final f1 = await _tempFile('o.png');
    final api = FakeDiscordApi(delay: const Duration(milliseconds: 700));
    final engine = UploadEngine(
      api: api,
      backoffSeconds: const [0, 0, 0],
      watchdogTick: const Duration(milliseconds: 20),
    );

    final events = <UploadProgress>[];
    final sub = engine.progressStream.listen(events.add);

    final fut = engine.run(
      items: [_item(f1)],
      config: _cfg(),
      caption: '',
      onBatchFailed: _noopBatchFailed,
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));
    engine.pause(); // jeda SEMASA batch dalam penerbangan
    final List<UploadProgress> pausedSeen = await Future<List<UploadProgress>>
        .delayed(const Duration(milliseconds: 350), () => events);

    // Semua peristiwa selepas jeda TIDAK berstatus 'running'.
    var sawPaused = false;
    for (final e in pausedSeen) {
      if (e.state == EngineState.paused) sawPaused = true;
      if (sawPaused && e.state == EngineState.running) {
        fail('state kembali running sedangkan masih dijeda (bug B09)');
      }
    }
    expect(sawPaused, isTrue, reason: 'status paused mesti dipancarkan');

    engine.resume();
    final status = await fut;
    sub.cancel();
    expect(status, 'completed');
  });
}
