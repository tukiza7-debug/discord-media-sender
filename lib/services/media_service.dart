import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
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

  // ------------------------------------------------------------- picking

  /// Pilih fail media (galeri/fail) melalui SAF — tiada kebenaran storan
  /// diperlukan.
  Future<MediaPickResult> pickMediaFiles() async {
    final res = await FilePicker.pickFiles(
      dialogTitle: 'Pick media files',
      type: FileType.custom,
      allowedExtensions: MediaCatalog.allowedExtensions,
      compressionQuality: 0,
    );
    if (res.isEmpty) return const MediaPickResult(items: []);
    return _validate(res.map(_fromPlatform).toList());
  }

  /// Pilih ZIP dan ekstrak semua media di dalamnya secara automatik.
  Future<MediaPickResult> pickZip() async {
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
    return extractZip(zipPath);
  }

  /// Pilih folder ('Send Folder') dan imbas semua subfolder.
  ///
  /// FIX: kebenaran baca media diminta dahulu — tanpanya, Directory.list
  /// gagal pada Android 10+ dan paparan media tidak muncul. Imbasan
  /// dijalankan dalam isolate latar supaya UI kekal responsif dan hasil
  /// dipaparkan serta-merta selepas imbasan selesai.
  Future<MediaPickResult> pickFolder() async {
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

    final res = await scanFolder(dirPath);
    // Maklum balas jelas jika folder tiada media (bukan senyap).
    if (res.items.isEmpty && res.skipped.isEmpty && res.info == null) {
      return const MediaPickResult(
        items: [],
        info: 'No supported media files found in this folder',
      );
    }
    return res;
  }

  // ----------------------------------------------------------- scanning

  /// Imbas folder secara rekursif dan kumpulkan semua media.
  ///
  /// Dijalankan dalam isolate berasingan (Isolate.run) supaya folder besar
  /// tidak membekukan UI; senarai media dipaparkan sebaik imbasan siap.
  Future<MediaPickResult> scanFolder(String rootPath) {
    return Isolate.run(() => scanFolderSync(rootPath));
  }

  /// Pelaksanaan segerak imbasan folder — dipanggil dalam isolate latar.
  ///
  /// Laluan rekursif tahan-gagal: subfolder yang tidak boleh dibaca
  /// dilangkau (tidak menggagalkan keseluruhan imbasan) dan fail tersembunyi
  /// (bermula dengan '.') diabaikan.
  static MediaPickResult scanFolderSync(String rootPath) {
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
    return _validate(found.map(_fromFile).toList());
  }

  /// Ekstrak ZIP ke folder sementara dan pulangkan senarai media di dalamnya.
  Future<MediaPickResult> extractZip(String zipPath) async {
    final zf = File(zipPath);
    if (!zf.existsSync()) {
      return const MediaPickResult(items: [], info: 'ZIP file not found');
    }
    if (zf.lengthSync() > AppLimits.maxZipBytes) {
      return const MediaPickResult(
          items: [], info: 'ZIP file exceeds the 1 GB limit and was skipped');
    }
    try {
      final bytes = zf.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final outDir = Directory(
          '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}zip_$stamp');
      outDir.createSync(recursive: true);

      final extracted = <File>[];
      for (final entry in archive) {
        if (entry.isFile) {
          final name = entry.name.split('/').last;
          if (!MediaCatalog.isSupported(name)) continue;
          // Abaiai entri sistem tersembunyi
          if (name.startsWith('._') || name.startsWith('.DS_Store')) continue;
          final dest = File('${outDir.path}${Platform.pathSeparator}$name');
          dest.writeAsBytesSync(entry.content as List<int>);
          extracted.add(dest);
          if (extracted.length >= AppLimits.maxFiles) break;
        }
      }
      archive.clear();
      if (extracted.isEmpty) {
        return const MediaPickResult(
            items: [], info: 'No media files inside this ZIP');
      }
      return _validate(extracted.map(_fromFile).toList(),
          context: 'ZIP: ${zipPath.split('/').last}');
    } catch (err) {
      return MediaPickResult(items: const [], info: 'Failed to extract ZIP: $err');
    }
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

  static MediaPickResult _validate(List<MediaFile> files, {String? context}) {
    final items = <MediaItem>[];
    final skipped = <String>[];

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
      final isImage = MediaCatalog.isImage(f.name);
      final limit = isImage ? AppLimits.maxImageBytes : AppLimits.maxVideoBytes;
      if (f.sizeBytes > limit) {
        final limitLabel = isImage ? '25 MB (image)' : '1 GB (video)';
        items.add(_item(f, MediaStatus.oversized, 'Exceeds the $limitLabel limit'));
        skipped.add('${f.name} — exceeds the $limitLabel limit');
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

  /// Semak fail masih wujud sebelum hantar (kembalikan senarai sedia).
  static List<MediaItem> existingOnly(List<MediaItem> items) => items
      .where((m) => m.status.canSend && File(m.path).existsSync())
      .toList(growable: false);
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
