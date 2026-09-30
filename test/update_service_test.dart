import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/core/secure_store.dart';
import 'package:discord_media_sender/services/update_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --------------------------------------------------- 1a: banding versi

  group('version comparison (1a)', () {
    test('1.0.10 > 1.0.9 (banding berangka, bukan leksikal)', () {
      expect(UpdateService.compareVersions('1.0.10', '1.0.9'), 1);
      expect(UpdateService.compareVersions('1.0.9', '1.0.10'), -1);
    });

    test('versi sama → 0; hanya LEBIH BAHARU dikira kemas kini', () {
      expect(UpdateService.compareVersions('1.0.9', '1.0.9'), 0);
      expect(UpdateService.compareVersions('1.0.8', '1.0.9'), -1);
    });

    test('panjang berbeza — sifar ditambah (1.0 == 1.0.0)', () {
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.0.1', '1.0'), 1);
    });

    test('tag tidak boleh dipecah → null (diabaikan tanpa crash)', () {
      expect(UpdateService.compareVersions('beta', '1.0.9'), null);
      expect(UpdateService.compareVersions('1.0.x', '1.0.9'), null);
      expect(UpdateService.compareVersions('', '1.0.9'), null);
    });

    test('parseVersion membuang awalan v', () {
      expect(UpdateService.parseVersion('v1.0.9'), [1, 0, 9]);
      expect(UpdateService.parseVersion('1.0.10'), [1, 0, 10]);
    });
  });

  // -------------------------------------- 1a: parse JSON keluaran GitHub

  group('release JSON parsing (1a)', () {
    test('keluaran penuh dipecah dengan betul', () {
      final r = GithubRelease.fromJson({
        'tag_name': 'v1.0.10',
        'body': 'Notes here',
        'html_url': 'https://github.com/tukiza7-debug/discord-media-sender/releases/tag/v1.0.10',
        'assets': [
          {
            'name': 'DiscordMediaSender-v1.0.10-universal.apk',
            'size': 42000000,
            'browser_download_url':
                'https://github.com/tukiza7-debug/discord-media-sender/releases/download/v1.0.10/DiscordMediaSender-v1.0.10-universal.apk',
          },
        ],
      });
      expect(r, isNotNull);
      expect(r!.tag, '1.0.10');
      expect(r.assets, hasLength(1));
      expect(r.assets.first.size, 42000000);
    });

    test('assets TIADA → senarai kosong, tidak melempar (ujian wajib)', () {
      final r = GithubRelease.fromJson({
        'tag_name': 'v1.0.10',
        'body': 'Notes',
        'html_url': 'https://github.com/x/y',
      });
      expect(r, isNotNull);
      expect(r!.assets, isEmpty);
    });

    test('format tidak dijangka / tag kosong → null (selamat)', () {
      expect(GithubRelease.fromJson({'tag_name': ''}), isNull);
      expect(GithubRelease.fromJson(<String, dynamic>{}), isNull);
    });
  });

  // -------------------------------------------------- 1d: pilih aset ABI

  group('ABI asset selection (1d)', () {
    GithubAsset asset(String name) => GithubAsset(
          name: name,
          size: 1,
          browserDownloadUrl: 'https://github.com/x/y/releases/download/v1.0.9/$name',
        );

    final assets = [
      asset('DiscordMediaSender-v1.0.9-universal.apk'),
      asset('DiscordMediaSender-v1.0.9-armeabi-v7a.apk'),
      asset('DiscordMediaSender-v1.0.9-arm64-v8a.apk'),
      asset('DiscordMediaSender-v1.0.9-x86_64.apk'),
    ];

    test('ABI tertinggi peranti dipilih dahulu', () {
      final picked = UpdateService.pickApkAsset(
          deviceAbis: ['arm64-v8a', 'armeabi-v7a', 'x86_64'], assets: assets);
      expect(picked!.name, contains('arm64-v8a'));
    });

    test('turutan ABI peranti dihormati (armeabi dahulu → pilih v7a)', () {
      final picked = UpdateService.pickApkAsset(
          deviceAbis: ['armeabi-v7a'], assets: assets);
      expect(picked!.name, contains('armeabi-v7a'));
    });

    test('ABI tidak diketahui → gugur ke universal (fallback wajib)', () {
      final picked = UpdateService.pickApkAsset(
          deviceAbis: ['mips'], assets: assets);
      expect(picked!.name, contains('universal'));
    });

    test('ABI kosong / tidak diketahui → universal', () {
      expect(
          UpdateService.pickApkAsset(deviceAbis: [], assets: assets)!.name,
          contains('universal'));
    });

    test('tiada universal & tiada padanan → null (tiada crash)', () {
      final picked = UpdateService.pickApkAsset(
        deviceAbis: ['mips'],
        assets: [asset('other.apk')],
      );
      expect(picked, isNull);
    });
  });

  // ---------------------------------------- 1d: SHA256SUMS + fail-closed

  group('SHA256SUMS parsing & verification (1d, fail closed)', () {
    late Directory tmp;
    late File apk;
    const goodHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('dms_update_test');
      apk = File('${tmp.path}/app.apk');
      await apk.writeAsBytes(List.filled(2048, 7));
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    test('parseChecksums: format sha256sum (<hash>  <nama>)', () {
      final map = UpdateService.parseChecksums(
          '$goodHash  DiscordMediaSender-v1.0.9-arm64-v8a.apk\n'
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  other.apk\n');
      expect(map['DiscordMediaSender-v1.0.9-arm64-v8a.apk'], goodHash);
      expect(map, hasLength(2));
    });

    test('checksum sepadan → null (OK)', () async {
      final real = await UpdateService.sha256OfFile(apk.path);
      final err = await UpdateService.verifyDownload(
        apk: apk,
        asset: GithubAsset(
            name: 'app.apk', size: 2048, browserDownloadUrl: 'https://github.com/x/y'),
        sumsText: '$real  app.apk\n',
      );
      expect(err, isNull);
      expect(apk.existsSync(), isTrue); // sah — fail kekal utk pemasangan
    });

    test('checksum TIDAK sepadan → ralat + fail dibuang (fail closed)', () async {
      final err = await UpdateService.verifyDownload(
        apk: apk,
        asset: GithubAsset(
            name: 'app.apk', size: 2048, browserDownloadUrl: 'https://github.com/x/y'),
        sumsText: '$goodHash  app.apk\n',
      );
      expect(err, isNotNull);
      expect(err, contains('mismatch'));
      expect(apk.existsSync(), isFalse);
    });

    test('entri TIADA dalam SHA256SUMS → ralat + fail dibuang', () async {
      final err = await UpdateService.verifyDownload(
        apk: apk,
        asset: GithubAsset(
            name: 'app.apk', size: 2048, browserDownloadUrl: 'https://github.com/x/y'),
        sumsText: '$goodHash  some-other-file.apk\n',
      );
      expect(err, isNotNull);
      expect(err, contains('missing'));
      expect(apk.existsSync(), isFalse);
    });

    test('saiz tak sepadan dgn aset → ralat + fail dibuang', () async {
      final err = await UpdateService.verifyDownload(
        apk: apk,
        asset: GithubAsset(
            name: 'app.apk', size: 999999, browserDownloadUrl: 'https://github.com/x/y'),
        sumsText: '$goodHash  app.apk\n',
      );
      expect(err, isNotNull);
      expect(apk.existsSync(), isFalse);
    });

    test('sha256OfFile menghasilkan hex 64 aksara', () async {
      final h = await UpdateService.sha256OfFile(apk.path);
      expect(h, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h!), isTrue);
    });
  });

  // --------------------------------------- 1b/1c: throttle & versi dilangkau

  group('check throttle & skipped-version persistence (1b/1c)', () {
    setUp(() {
      FlutterSecureStoragePlatform.instance =
          TestFlutterSecureStoragePlatform({});
    });

    test('throttle: belum tiba masanya / sudah tiba masanya', () async {
      await SecureStore.saveLastUpdateCheckMs(DateTime.now().millisecondsSinceEpoch);
      expect(await UpdateService.isAutoCheckDue(), isFalse);

      await SecureStore.saveLastUpdateCheckMs(
          DateTime.now().millisecondsSinceEpoch -
              AppLimits.updateAutoCheckIntervalMs -
              1000);
      expect(await UpdateService.isAutoCheckDue(), isTrue);
    });

    test('versi dilangkau kekal selepas tulis & baca', () async {
      await UpdateService.skipVersion('v1.0.10');
      expect(await UpdateService.skippedTag(), 'v1.0.10');
      await UpdateService.skipVersion('');
      expect(await UpdateService.skippedTag(), '');
    });

    test('auto update lalai ON (1b)', () async {
      expect(await SecureStore.loadAutoUpdate(), isTrue);
      await SecureStore.saveAutoUpdate(false);
      expect(await SecureStore.loadAutoUpdate(), isFalse);
    });
  });

  // --------------------------------------------- 1d: URL dibenarkan

  group('download URL host allowlist (1d)', () {
    test('github.com & release-asset hosts dibenarkan', () {
      expect(
          UpdateService.isAllowedDownloadUrl(
              'https://github.com/tukiza7-debug/discord-media-sender/releases/download/v1.0.9/app.apk'),
          isTrue);
      expect(
          UpdateService.isAllowedDownloadUrl(
              'https://objects.githubusercontent.com/x/app.apk'),
          isTrue);
      expect(
          UpdateService.isAllowedDownloadUrl(
              'https://release-assets.githubusercontent.com/x/app.apk'),
          isTrue);
    });

    test('bukan-https / host asing DITOLAK', () {
      expect(
          UpdateService.isAllowedDownloadUrl('http://github.com/x/app.apk'),
          isFalse);
      expect(
          UpdateService.isAllowedDownloadUrl('https://evil.example/app.apk'),
          isFalse);
      expect(
          UpdateService.isAllowedDownloadUrl('https://github.com.evil.example/a.apk'),
          isFalse);
      expect(UpdateService.isAllowedDownloadUrl('not a url'), isFalse);
    });
  });

  group('dio factory seam', () {
    test('checkLatest menangkap ralat rangkaian → ok:false + mesej', () async {
      UpdateService.dioFactory = () {
        final d = Dio();
        d.httpClientAdapter = _OfflineAdapter();
        return d;
      };
      addTearDown(() => UpdateService.dioFactory = null);
      final r = await UpdateService.checkLatest(currentVersion: '1.0.9');
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
      expect(r.updateAvailable, isFalse);
    });

    test('checkLatest menghormati User-Agent & Accept (disahkan di adapter)',
        () async {
      String? ua;
      String? accept;
      UpdateService.dioFactory = () {
        final d = Dio();
        d.httpClientAdapter = _CaptureAdapter((opts) {
          ua = opts.headers['User-Agent'] as String?;
          accept = opts.headers['Accept'] as String?;
        });
        return d;
      };
      addTearDown(() => UpdateService.dioFactory = null);
      final r = await UpdateService.checkLatest(currentVersion: '1.0.9');
      expect(r.ok, isTrue);
      expect(ua, 'DiscordMediaSender/1.0.9');
      expect(accept, 'application/vnd.github+json');
    });

    test('tag lebih baharu → updateAvailable; tag tidak sah → diabaikan',
        () async {
      UpdateService.dioFactory = () {
        final d = Dio();
        d.httpClientAdapter = _ReleaseAdapter('v1.0.10');
        return d;
      };
      addTearDown(() => UpdateService.dioFactory = null);
      final newer = await UpdateService.checkLatest(currentVersion: '1.0.9');
      expect(newer.updateAvailable, isTrue);

      UpdateService.dioFactory = () {
        final d = Dio();
        d.httpClientAdapter = _ReleaseAdapter('beta-thing');
        return d;
      };
      final bad = await UpdateService.checkLatest(currentVersion: '1.0.9');
      expect(bad.ok, isTrue);
      expect(bad.updateAvailable, isFalse); // tag tidak sah → bukan update
    });
  });
}

// ---------------------------------------------------------------- adapter

class _OfflineAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException.connectionError(
        requestOptions: options, reason: 'offline');
  }
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.onRequest);
  final void Function(RequestOptions options) onRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    onRequest(options);
    return ResponseBody.fromString(
        jsonEncode({'tag_name': 'v1.0.9', 'assets': []}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
}

class _ReleaseAdapter implements HttpClientAdapter {
  _ReleaseAdapter(this.tag);
  final String tag;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
        jsonEncode({'tag_name': tag, 'assets': []}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }
}
