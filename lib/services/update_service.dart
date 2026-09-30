import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart' as ofx;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/secure_store.dart';

/// Aset APK dalam satu keluaran GitHub (1a).
class GithubAsset {
  const GithubAsset({
    required this.name,
    required this.size,
    required this.browserDownloadUrl,
  });
  final String name;
  final int size;
  final String browserDownloadUrl;
}

/// Satu keluaran GitHub (1a) — tag dibersihkan daripada awalan 'v'.
class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  final String tagName; // asal, cth. 'v1.0.9'
  final String body; // nota keluaran (dari CHANGELOG)
  final String htmlUrl;
  final List<GithubAsset> assets;

  /// Tag tanpa awalan 'v' — versi X.Y.Z (mungkin tidak sah untuk dipecah).
  String get tag => tagName.startsWith('v') ? tagName.substring(1) : tagName;

  static GithubRelease? fromJson(Map<String, dynamic> j) {
    try {
      final tagName = (j['tag_name'] ?? '') as String;
      if (tagName.isEmpty) return null;
      final rawAssets = j['assets'];
      final assets = <GithubAsset>[];
      if (rawAssets is List) {
        for (final a in rawAssets) {
          if (a is Map) {
            final name = (a['name'] ?? '') as String;
            final url = (a['browser_download_url'] ?? '') as String;
            if (name.isEmpty || url.isEmpty) continue;
            assets.add(GithubAsset(
              name: name,
              size: (a['size'] as num?)?.toInt() ?? 0,
              browserDownloadUrl: url,
            ));
          }
        }
      }
      // assets TIADA / kosong → senarai kosong (tidak melempar).
      return GithubRelease(
        tagName: tagName,
        body: (j['body'] ?? '') as String,
        htmlUrl: (j['html_url'] ?? '') as String,
        assets: assets,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Keputusan semakan keluaran (1a).
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.ok,
    this.error,
    this.release,
    this.updateAvailable = false,
  });
  final bool ok;
  final String? error; // sebab kegagalan (semakan manual)
  final GithubRelease? release;
  final bool updateAvailable;

  bool get upToDate => ok && !updateAvailable;
}

/// Keputusan muat turun (1d).
class UpdateDownloadResult {
  const UpdateDownloadResult({
    required this.ok,
    this.error,
    this.file,
    this.cancelled = false,
  });
  final bool ok;
  final String? error;
  final File? file;
  final bool cancelled;
}

/// Keputusan aliran kemas kini penuh (muat turun + sahkan + pasang).
class UpdateFlowResult {
  const UpdateFlowResult({required this.ok, this.error, this.cancelled = false});
  final bool ok;
  final String? error;
  final bool cancelled;
}

/// Servis kemas kini automatik daripada GitHub (CHANGE 1).
///
/// KESELAMATAN: tiada token auth, tiada data pengguna dihantar; muat turun
/// hanya dari https://github.com atau host release-asset GitHub; pemasangan
/// GAGAL-TERTUTUP — checksum SHA-256 + saiz mesti sepadan sebelum dipasang.
class UpdateService {
  UpdateService._();

  static const _latestUrl =
      'https://api.github.com/repos/tukiza7-debug/discord-media-sender/releases/latest';

  /// Host yang dibenarkan untuk muat turun (1d). Host release-asset yang
  /// dipulangkan API GitHub untuk aset repositori ini.
  static const _allowedHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };

  /// ABI yang disokong oleh pakej APK split (1d).
  static const _apkAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];

  @visibleForTesting
  static Dio Function()? dioFactory;

  static Dio _dio() {
    final factory = dioFactory;
    if (factory != null) return factory();
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  // --------------------------------------------------------- versi (1a)

  /// Pecahkan versi kepada segmen berangka X.Y.Z — null jika tidak sah.
  @visibleForTesting
  static List<int>? parseVersion(String version) {
    var v = version.trim();
    if (v.startsWith('v')) v = v.substring(1);
    if (v.isEmpty) return null;
    final parts = v.split('.');
    if (parts.isEmpty || parts.length > 4) return null;
    final out = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0) return null;
      out.add(n);
    }
    return out;
  }

  /// Bandingkan dua versi X.Y.Z (segmen berangka, sifar ditambah). -1/0/1;
  /// null jika mana-mana tidak boleh dipecah (abaikan tanpa crash).
  @visibleForTesting
  static int? compareVersions(String a, String b) {
    final va = parseVersion(a);
    final vb = parseVersion(b);
    if (va == null || vb == null) return null;
    final len = va.length > vb.length ? va.length : vb.length;
    for (var i = 0; i < len; i++) {
      final x = i < va.length ? va[i] : 0;
      final y = i < vb.length ? vb[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  // -------------------------------------------------------- semak (1a/1b)

  /// Semak keluaran terkini. SEMUA ralat ditangkap — pemanggil memutuskan
  /// senyap (automatik) atau papar mesej (manual).
  static Future<UpdateCheckResult> checkLatest({
    required String currentVersion,
    Dio? dio,
  }) async {
    try {
      final d = dio ?? _dio();
      final resp = await d.get<Map<String, dynamic>>(
        _latestUrl,
        options: Options(headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'DiscordMediaSender/$currentVersion',
        }),
      );
      final data = resp.data;
      if (data == null) {
        return const UpdateCheckResult(ok: false, error: 'Empty response from GitHub');
      }
      final release = GithubRelease.fromJson(data);
      if (release == null) {
        return const UpdateCheckResult(ok: false, error: 'Unexpected response from GitHub');
      }
      // Tag yang tidak boleh dipecah diabaikan — tidak dikira kemas kini.
      final cmp = compareVersions(release.tag, currentVersion);
      final available = cmp != null && cmp > 0; // hanya LEBIH BAHARU
      return UpdateCheckResult(
          ok: true, release: release, updateAvailable: available);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      String msg;
      if (code == 403 || code == 429) {
        msg = 'GitHub rate limit reached. Try again later.';
      } else if (code != null) {
        msg = 'GitHub returned HTTP $code.';
      } else {
        msg = 'You appear to be offline.';
      }
      return UpdateCheckResult(ok: false, error: msg);
    } catch (_) {
      return const UpdateCheckResult(ok: false, error: 'Check failed.');
    }
  }

  /// 1b: adakah semakan automatik sudah tiba masanya (6 jam)?
  static Future<bool> isAutoCheckDue() async {
    final last = await SecureStore.loadLastUpdateCheckMs();
    return DateTime.now().millisecondsSinceEpoch - last >=
        AppLimits.updateAutoCheckIntervalMs;
  }

  /// Catat masa semakan automatik (dipanggil selepas SETIAP percubaan).
  static Future<void> markAutoChecked() =>
      SecureStore.saveLastUpdateCheckMs(DateTime.now().millisecondsSinceEpoch);

  static Future<String> skippedTag() => SecureStore.loadSkippedUpdateTag();

  static Future<void> skipVersion(String tag) =>
      SecureStore.saveSkippedUpdateTag(tag);

  // ------------------------------------------------- pilih aset ABI (1d)

  /// Pilih aset APK ikut ABI peranti (turutan tertinggi dahulu); gugur ke
  /// universal jika ABI tidak diketahui / tiada padanan.
  @visibleForTesting
  static GithubAsset? pickApkAsset({
    required List<String> deviceAbis,
    required List<GithubAsset> assets,
  }) {
    final apks = assets
        .where((a) => a.name.toLowerCase().endsWith('.apk'))
        .toList(growable: false);
    for (final abi in deviceAbis) {
      if (!_apkAbis.contains(abi)) continue;
      for (final a in apks) {
        if (a.name.toLowerCase().endsWith('-$abi.apk')) return a;
      }
    }
    for (final a in apks) {
      if (a.name.toLowerCase().endsWith('-universal.apk')) return a;
    }
    return null;
  }

  // -------------------------------------------------- muat turun (1d)

  /// URL hanya https://github.com atau host release-asset GitHub.
  @visibleForTesting
  static bool isAllowedDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.isScheme('https') && _allowedHosts.contains(uri.host);
  }

  static Directory _updatesDir(String tempPath) =>
      Directory('$tempPath/updates');

  /// Muat turun APK ke `<cache>/updates/` dgn kemajuan + boleh-batal.
  /// Fail separa DIBUANG pada sebarang kegagalan.
  static Future<UpdateDownloadResult> downloadApk({
    required GithubAsset asset,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    Dio? dio,
    Directory? destinationOverride, // @visibleForTesting
  }) async {
    if (!isAllowedDownloadUrl(asset.browserDownloadUrl)) {
      return const UpdateDownloadResult(
          ok: false, error: 'Download URL is not an official GitHub host.');
    }
    final dir = destinationOverride ??
        _updatesDir((await getTemporaryDirectory()).path);
    try {
      await dir.create(recursive: true);
    } catch (_) {}
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    try {
      final d = dio ?? _dio();
      await d.download(
        asset.browserDownloadUrl,
        file.path,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
      );
      return UpdateDownloadResult(ok: true, file: file);
    } on DioException catch (e) {
      await _deleteQuiet(file);
      if (e.type == DioExceptionType.cancel) {
        return const UpdateDownloadResult(ok: false, cancelled: true, error: 'Download cancelled.');
      }
      return UpdateDownloadResult(ok: false, error: 'Download failed: ${_brief(e)}');
    } catch (e) {
      await _deleteQuiet(file);
      return UpdateDownloadResult(ok: false, error: 'Download failed: ${_brief(e)}');
    }
  }

  // ---------------------------------------------------- sahkan (1d)

  /// Parse `sha256sum *.apk`: `<hash>  <nama>`.
  @visibleForTesting
  static Map<String, String> parseChecksums(String text) {
    final out = <String, String>{};
    final re = RegExp(r'^([0-9a-fA-F]{64})\s+(.+)$', multiLine: true);
    for (final m in re.allMatches(text)) {
      final name = m.group(2)!.trim();
      if (name.isNotEmpty) out[name] = m.group(1)!.toLowerCase();
    }
    return out;
  }

  /// FAIL-TERTUTUP: saiz mesti sepadan dgn aset + SHA-256 mesti sepadan
  /// dgn baris SHA256SUMS.txt. Fail dibuang pada sebarang kegagalan.
  /// Kembalikan null jika sah; mesej ralat jika tidak.
  static Future<String?> verifyDownload({
    required File apk,
    required GithubAsset asset,
    required String sumsText,
  }) async {
    Future<String?> fail(String message) async {
      await _deleteQuiet(apk);
      return message;
    }

    // 1. Saiz mesti sama dengan metadata aset.
    final actualSize = apk.lengthSync();
    if (asset.size > 0 && actualSize != asset.size) {
      return fail('Downloaded file size ($actualSize bytes) does not match '
          'the release (${asset.size} bytes).');
    }

    // 2. Entri checksum wajib wujud.
    final expected = parseChecksums(sumsText)[asset.name];
    if (expected == null) {
      return fail('Checksum entry for ${asset.name} is missing in '
          'SHA256SUMS.txt.');
    }

    // 3. SHA-256 streaming (tidak memuatkan APK penuh ke memori).
    final actual = await sha256OfFile(apk.path);
    if (actual == null) {
      return fail('Could not read the downloaded file to verify it.');
    }
    if (actual != expected) {
      return fail('Checksum mismatch — the download may be corrupted or '
          'tampered with.');
    }
    return null;
  }

  @visibleForTesting
  static Future<String?> sha256OfFile(String path) async {
    try {
      final collector = _DigestCollector();
      final input = crypto.sha256.startChunkedConversion(collector);
      await for (final chunk in File(path).openRead()) {
        input.add(chunk);
      }
      input.close();
      return collector.value?.toString();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------- pasang (1d)

  /// Minta kebenaran "install unknown apps" kemudian buka APK dgn pemasang
  /// sistem. Gagal → mesej ralat (paparan URL keluaran oleh UI).
  static Future<String?> installApk(String apkPath) async {
    try {
      var status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        status = await Permission.requestInstallPackages.request();
      }
      if (!status.isGranted) {
        return 'Permission to install apps was denied.';
      }
    } catch (_) {
      return 'Could not request the install permission.';
    }
    try {
      final res = await ofx.OpenFilex.open(apkPath);
      if (res.type == ofx.ResultType.done) return null;
      return 'Installer error: ${res.message}';
    } catch (e) {
      return 'Installer error: ${_brief(e)}';
    }
  }

  /// Buang baki fail kemas kini (semasa app mula + selepas cuba pasang, 1d).
  static Future<void> clearDownloadedFiles() async {
    try {
      final dir = _updatesDir((await getTemporaryDirectory()).path);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  // --------------------------------------------------------- aliran penuh

  /// Muat turun → sahkan → pasang. DIPANGGIL HANYA apabila tiada sesi
  /// hantaran aktif (1c/3c — butang "Update now" dilumpuhkan semasa sesi).
  static Future<UpdateFlowResult> runUpdateFlow({
    required GithubRelease release,
    required List<String> deviceAbis,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final asset = pickApkAsset(deviceAbis: deviceAbis, assets: release.assets);
    if (asset == null) {
      return const UpdateFlowResult(
          ok: false, error: 'No suitable APK asset found in this release.');
    }

    // SHA256SUMS.txt dari keluaran yang SAMA (1d).
    String? sumsText;
    try {
      final sumsAsset = release.assets.firstWhere(
        (a) => a.name == 'SHA256SUMS.txt',
      );
      if (!isAllowedDownloadUrl(sumsAsset.browserDownloadUrl)) {
        return const UpdateFlowResult(
            ok: false, error: 'Checksum URL is not an official GitHub host.');
      }
      final d = _dio();
      final resp = await d.get<String>(
        sumsAsset.browserDownloadUrl,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain),
      );
      sumsText = resp.data;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return const UpdateFlowResult(ok: false, cancelled: true);
      }
      // SHA256SUMS.txt TIADA → gagal-tertutup (jangan pasang).
      return const UpdateFlowResult(
          ok: false,
          error: 'SHA256SUMS.txt is missing from this release — the APK '
              'cannot be verified, so it was not installed.');
    } catch (_) {
      return const UpdateFlowResult(
          ok: false,
          error: 'Could not download SHA256SUMS.txt — the APK cannot be '
              'verified, so it was not installed.');
    }

    final dl = await downloadApk(
        asset: asset,
        onProgress: onProgress,
        cancelToken: cancelToken);
    if (!dl.ok || dl.file == null) {
      return UpdateFlowResult(
          ok: false, cancelled: dl.cancelled, error: dl.error);
    }

    final verifyError = await verifyDownload(
        apk: dl.file!, asset: asset, sumsText: sumsText ?? '');
    if (verifyError != null) {
      return UpdateFlowResult(ok: false, error: verifyError);
    }

    final installError = await installApk(dl.file!.path);
    // Selepas cubaan pasang — buang fail kemas kini (1d).
    await _deleteQuiet(dl.file!);
    if (installError != null) {
      return UpdateFlowResult(ok: false, error: installError);
    }
    return const UpdateFlowResult(ok: true);
  }

  // ------------------------------------------------------------ bantu

  static Future<void> _deleteQuiet(File f) async {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  static String _brief(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}

/// Penerima hasil hashing ber-cebis (crypto tidak mengeksport DigestSink).
class _DigestCollector implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest d) => value = d;

  @override
  void close() {}
}
