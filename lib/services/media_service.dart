import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' show InputFileStream;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../models/models.dart';

/// Keputusan operasi pilih media.
class MediaPickResult {
  const MediaPickResult({required this.items, this.skipped = const [], this.info});
  final List<MediaItem> items;
  final List<String> skipped; // sebab dilangkau
  final String? info;
}

/// Servis pemilihan, pengimbasan dan pengesahan media.
class MediaService {
  const MediaService._();

  static const MediaService instance = MediaService._();

  /// Folder sementara ZIP yang dicipta — dibersihkan semasa app dimulakan
  /// (B10: dulu kekal selamanya dalam temp dir).
  static final List<String> _zipTempDirs = [];

  /// Buang semua folder sementara ekstrak ZIP (dipanggil semasa app mula).
  static void cleanupZipTemp() {
    for (final path in List<String>.from(_zipTempDirs)) {
      try {
        final d = Directory(path);
        if (d.existsSync()) d.deleteSync(recursive: true);
        _zipTempDirs.remove(path);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------- picking

  /// Pilih fail media (galeri/fail) melalui SAF — tiada kebenaran storan
  /// diperlukan. V1 DISAHKAN: dalam file_picker 13.x, pickFiles pulangkan
  /// `List<PlatformFile>` — pilihan BERBILANG ialah kelakian lalai (tiada
  /// lagi parameter `allowMultiple` seperti v8-v10).
  Future<MediaPickResult> pickMediaFiles({int maxFileMB = AppLimits.defaultMaxFileMB}) async {
    final res = await FilePicker.pickFiles(
      dialogTitle: 'Pick media files',
      type: FileType.custom,
      allowedExtensions: MediaCatalog.allowedExtensions,
      compressionQuality: 0,
    );
    if (res.isEmpty) return const MediaPickResult(items: []);
    return _validate(res.map(_fromPlatform).toList(), maxFileMB: maxFileMB);
  }

  /// Pilih ZIP dan ekstrak semua media di dalamnya secara automatik.
  Future<MediaPickResult> pickZip({int maxFileMB = AppLimits.defaultMaxFileMB}) async {
    final res = await FilePicker.pickFiles(
      dialogTitle: 'Pick a ZIP file',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (res.isEmpty) return const MediaPickResult(items: []);
    final f = res.first;
    final zipPath = f.path;
    if (zipPath == null) {
      return const MediaPickResult(items: [], info: 'Invalid ZIP file');
    }
    final result = await extractZip(zipPath, maxFileMB: maxFileMB);
    // B10: bersihkan fail sementara picker selepas selesai (API disemak:
    // wujud dalam file_picker 13.1.0).
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
    return result;
  }

  /// Pilih folder ('Send Folder') dan imbas semua subfolder.
  ///
  /// Kebenaran baca media diminta dahulu — tanpanya, Directory.list
  /// gagal pada Android 10+ dan paparan media tidak muncul. Imbasan
  /// dijalankan dalam isolate latar supaya UI kekal responsif dan hasil
  /// dipaparkan serta-merta selepas imbasan selesai.
  Future<MediaPickResult> pickFolder({int maxFileMB = AppLimits.defaultMaxFileMB}) async {
    final dirPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Pick a media folder',
    );
    if (dirPath == null) return const MediaPickResult(items: []);

    // Kebenaran baca media (foto & video) diperlukan untuk membaca kandungan
    // folder melalui laluan fail terus.
    final granted = await ensureMediaReadPermission();
    if (!granted) {
      return const MediaPickResult(
        items: [],
        info: 'Photo & video access permission is required to scan '
            'folders. Allow it in System Settings → Permissions.',
      );
    }

    final res = await scanFolder(dirPath, maxFileMB: maxFileMB);
    // Maklum balas jelas jika folder tiada media (bukan senyap).
    if (res.items.isEmpty && res.skipped.isEmpty && res.info == null) {
      // B19: akses separa (Android 14+ 'Select photos') — beri mesej
      // khusus bahawa hanya item terpilih pengguna yang kelihatan.
      if (await _hasLimitedMediaAccess()) {
        return const MediaPickResult(
          items: [],
          info: 'Only user-selected photos/videos are visible '
              '(limited media access). Allow all media access in '
              'System Settings → Permissions to scan the whole folder.',
        );
      }
      return const MediaPickResult(
        items: [],
        info: 'No supported media files found in this folder',
      );
    }
    return res;
  }

  Future<bool> _hasLimitedMediaAccess() async {
    try {
      return await Permission.photos.status == PermissionStatus.limited ||
          await Permission.videos.status == PermissionStatus.limited;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------------- scanning

  /// Imbas folder secara rekursif dan kumpulkan semua media.
  ///
  /// Dijalankan dalam isolate berasingan (Isolate.run) supaya folder besar
  /// tidak membekukan UI; senarai media dipaparkan sebaik imbasan siap.
  Future<MediaPickResult> scanFolder(String rootPath, {int maxFileMB = AppLimits.defaultMaxFileMB}) {
    return Isolate.run(() => scanFolderSync(rootPath, maxFileMB: maxFileMB));
  }

  /// Pelaksanaan segerak imbasan folder — dipanggil dalam isolate latar.
  ///
  /// Laluan rekursif tahan-gagal: subfolder yang tidak boleh dibaca
  /// dilangkau (tidak menggagalkan keseluruhan imbasan), fail/direktori
  /// tersembunyi (bermula dengan '.') diabaikan.
  static MediaPickResult scanFolderSync(String rootPath, {int maxFileMB = AppLimits.defaultMaxFileMB}) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) {
      return const MediaPickResult(items: [], info: 'Folder not found');
    }

    final found = <File>[];
    var unreadableDirs = 0;

    void walk(Directory d) {
      List<FileSystemEntity> entities;
      try {
        entities = d.listSync(followLinks: false);
      } catch (_) {
        unreadableDirs++;
        return;
      }
      for (final e in entities) {
        try {
          if (e is Directory) {
            // B19: langkau direktori tersembunyi/sistem (.thumbnails, .trash…)
            final dirName = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
            if (dirName.startsWith('.')) continue;
            walk(e);
          } else if (e is File) {
            final name = e.uri.pathSegments.last;
            if (name.startsWith('.')) continue; // fail tersembunyi
            if (MediaCatalog.isSupported(name)) found.add(e);
          }
        } catch (_) {
          // Entri tidak boleh diakses — langkau sahaja.
        }
      }
    }

    walk(dir);

    // Jika folder akar sendiri tidak boleh dibaca, kemungkinan besar
    // kebenaran sistem belum diberikan — beri mesej khusus.
    if (found.isEmpty && unreadableDirs > 0) {
      try {
        dir.listSync(followLinks: false);
      } catch (_) {
        return const MediaPickResult(
          items: [],
          info: 'The folder could not be read. Check the app storage '
              'permission in System Settings.',
        );
      }
    }

    found.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return _validate(found.map(_fromFile).toList(), maxFileMB: maxFileMB);
  }

  /// Ekstrak ZIP ke folder sementara dan pulangkan senarai media di dalamnya.
  ///
  /// B10 — pembetulan besar:
  /// - ekstraksi berjalan dalam Isolate.run (UI tidak membeku, tiada ANR/OOM);
  /// - dibaca STRIM dari cakera (InputFileStream), bukan load penuh ke memori;
  /// - nama dilindungi: sublaluan relatif dikekal selepas sanitasi, entri
  ///   path-traversal (../, ..\) DITOLAK, nama berulang di-de-dup
  ///   deterministik ("name (1).jpg");
  /// - jumlah saiz selepas ekstrak dihadkan (pertahanan zip-bomb);
  /// - folder sementara dibuang semasa kegagalan + dilaporkan pengecutan
  ///   (truncation) dengan sebab jelas.
  Future<MediaPickResult> extractZip(
    String zipPath, {
    int maxFileMB = AppLimits.defaultMaxFileMB,
    Directory? destination, // @visibleForTesting — override lokasi output
  }) async {
    final zf = File(zipPath);
    if (!zf.existsSync()) {
      return const MediaPickResult(items: [], info: 'ZIP file not found');
    }
    if (zf.lengthSync() > AppLimits.maxZipBytes) {
      return const MediaPickResult(
          items: [], info: 'ZIP file exceeds the 1 GB limit and was skipped');
    }

    final outDir = destination ??
        Directory(
            '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}zip_${DateTime.now().millisecondsSinceEpoch}');

    try {
      final result = await Isolate.run(() => _extractZipSync(zf.path, outDir.path));
      if (result.items.isEmpty) {
        _removeDirQuiet(outDir.path);
      } else {
        _zipTempDirs.add(outDir.path);
      }
      if (result.items.isEmpty && result.skipped.isEmpty) {
        return MediaPickResult(
            items: const [], info: 'No media files inside this ZIP');
      }
      return _validate(
        result.items.map(_fromFile).toList(),
        maxFileMB: maxFileMB,
        context: 'ZIP: ${zipPath.split(Platform.pathSeparator).last}',
        extraSkipped: result.skipped,
      );
    } catch (err) {
      _removeDirQuiet(outDir.path);
      return MediaPickResult(items: const [], info: 'Failed to extract ZIP: $err');
    }
  }

  static void _removeDirQuiet(String path) {
    try {
      final d = Directory(path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Ekstraksi segerak — dijalankan DALAM ISOLAT (dipanggil Isolate.run).
  ///
  /// MEMORI: struktur ZIP dibaca dari cakera (InputFileStream, bukan load
  /// penuh); setiap entri didekompres satu demi satu dan dibebaskan —
  /// puncak memori = fail terbesar, bukan saiz penuh ZIP.
  static _ZipExtractResult _extractZipSync(String zipPath, String outDirPath) {
    final outDir = Directory(outDirPath);
    outDir.createSync(recursive: true);

    final extracted = <File>[];
    final skipped = <String>[];
    final usedNames = <String>{};
    var totalBytes = 0;

    // Baca STRIM dari cakera — struktur ZIP tidak dimuat penuh ke memori.
    final input = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeBuffer(input);
    try {
      for (final entry in archive) {
        if (extracted.length >= AppLimits.maxFiles) {
          skipped.add('some entries skipped — exceeds the '
              '${AppLimits.maxFiles} file limit');
          break;
        }
        if (!entry.isFile) continue;

        // Nama mentah: kendalikan '\\', pecahkan segmen laluan.
        final rawName = entry.name.replaceAll('\\', '/');
        final segments = rawName.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty) continue;

        // Path-traversal: sebarang '..' → TOLAK entri ini.
        if (segments.contains('..')) {
          skipped.add('$rawName — rejected (invalid path)');
          continue;
        }
        final base = segments.last;
        if (base.startsWith('.')) continue; // entri sistem tersembunyi
        if (!MediaCatalog.isSupported(base)) continue;

        // De-dup deterministik: IMG_001.jpg → 'IMG_001 (1).jpg', (2), …
        var finalName = base;
        var counter = 1;
        while (usedNames.contains(finalName.toLowerCase())) {
          final dot = base.lastIndexOf('.');
          final stem = dot < 0 ? base : base.substring(0, dot);
          final ext = dot < 0 ? '' : base.substring(dot);
          finalName = '$stem ($counter)$ext';
          counter++;
        }
        usedNames.add(finalName.toLowerCase());

        // Pertahanan zip-bomb: semak SAIZ TIDAK termampat (header) SEBELUM
        // dekompres — jumlah diekstrak tidak melebihi had keselamatan.
        final uncompressed = entry.size;
        if (totalBytes + uncompressed > AppLimits.maxZipExtractBytes) {
          skipped.add('$base — skipped: extracted total exceeds the '
              '${AppLimits.maxZipExtractBytes ~/ (1024 * 1024)} MB safety cap');
          continue;
        }

        final dest = File('${outDir.path}${Platform.pathSeparator}$finalName');
        // archive 3.6.1: entry.content didekompres per-entri (puncak memori
        // = satu fail) — dibebaskan selepas setiap lelaran.
        final bytes = entry.content as List<int>;
        dest.writeAsBytesSync(bytes);
        totalBytes += uncompressed;
        extracted.add(dest);
      }
      archive.clear();
    } finally {
      input.closeSync();
    }

    return _ZipExtractResult(
      items: extracted,
      skipped: skipped,
      info: null,
    );
  }

  // -------------------------------------------------------- validation

  static MediaFile _fromPlatform(PlatformFile f) => MediaFile(
        path: f.path ?? '',
        name: f.name,
        sizeBytes: f.lengthSync() ?? 0,
      );

  static MediaFile _fromFile(File f) => MediaFile(
        path: f.path,
        name: f.uri.pathSegments.last,
        sizeBytes: f.lengthSync(),
      );

  /// B02: had saiz DINAMIK ikut tetapan pengguna (preset 10/20/50/100 MB,
  /// lalai 20 MB) — bukan lagi andaian 25 MB imej / 1 GB video.
  static MediaPickResult _validate(
    List<MediaFile> files, {
    String? context,
    int maxFileMB = AppLimits.defaultMaxFileMB,
    List<String> extraSkipped = const [],
  }) {
    final items = <MediaItem>[];
    final skipped = <String>[...extraSkipped];

    for (final f in files) {
      if (items.length >= AppLimits.maxFiles) {
        skipped.add('${f.name} — exceeds the ${AppLimits.maxFiles} file limit');
        continue;
      }
      if (f.path.isEmpty || !File(f.path).existsSync()) {
        skipped.add('${f.name} — file not found');
        continue;
      }
      if (!MediaCatalog.isSupported(f.name)) {
        skipped.add('${f.name} — unsupported file type');
        continue;
      }
      final limit = maxFileMB * 1024 * 1024;
      if (f.sizeBytes > limit) {
        items.add(_item(
            f, MediaStatus.oversized, 'Exceeds the $maxFileMB MB upload limit'));
        skipped.add('${f.name} — exceeds the $maxFileMB MB upload limit');
        continue;
      }
      items.add(_item(f, MediaStatus.ready, null));
    }

    return MediaPickResult(
      items: items,
      skipped: skipped,
      info: context,
    );
  }

  static MediaItem _item(MediaFile f, MediaStatus status, String? note) {
    final type = MediaCatalog.isVideo(f.name)
        ? MediaType.video
        : (MediaCatalog.isImage(f.name) ? MediaType.image : MediaType.other);
    return MediaItem(
      id: 'm-${f.path.hashCode}-${f.sizeBytes}',
      path: f.path,
      name: f.name,
      sizeBytes: f.sizeBytes,
      type: type,
      mimeType: MediaCatalog.mimeType(f.name),
      status: status,
      note: note,
    );
  }
}

/// Hasil ekstraksi ZIP dalaman (antara isolate).
class _ZipExtractResult {
  const _ZipExtractResult({
    required this.items,
    required this.skipped,
    required this.info,
  });
  final List<File> items;
  final List<String> skipped;
  final String? info;
}

/// Struktur dalaman ringan sebelum menjadi MediaItem.
@immutable
class MediaFile {
  const MediaFile({required this.path, required this.name, required this.sizeBytes});
  final String path;
  final String name;
  final int sizeBytes;
}

/// Minta kebenaran baca media (diperlukan untuk imbasan folder).
///
/// Android 13+: READ_MEDIA_IMAGES / READ_MEDIA_VIDEO (dan akses separa
/// 'limited' pada Android 14+ dianggap cukup).
/// Android 12 ke bawah: READ_EXTERNAL_STORAGE.
/// Meminta ketiga-tiga sekali gus adalah selamat: OS akan hanya papar
/// dialog bagi kebenaran yang relevan pada versi peranti tersebut.
Future<bool> ensureMediaReadPermission() async {
  // Bukan platform mudah alih (ujian/desktop): tiada kebenaran diperlukan.
  if (!Platform.isAndroid && !Platform.isIOS) return true;

  final results = await [
    Permission.photos,
    Permission.videos,
    Permission.storage,
  ].request();

  bool cukup(PermissionStatus? s) =>
      s == PermissionStatus.granted || s == PermissionStatus.limited;

  return cukup(results[Permission.photos]) ||
      cukup(results[Permission.videos]) ||
      cukup(results[Permission.storage]);
}
