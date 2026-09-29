import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih fail media',
      type: FileType.custom,
      allowedExtensions: MediaCatalog.allowedExtensions,
      allowMultiple: true,
      compressionQuality: 0,
      withData: false,
    );
    if (res == null) return const MediaPickResult(items: []);
    return _validate(res.files.map(_fromPlatform).toList());
  }

  /// Pilih ZIP dan ekstrak semua media di dalamnya secara automatik.
  Future<MediaPickResult> pickZip() async {
    final res = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih fail ZIP',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      allowMultiple: false,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return const MediaPickResult(items: []);
    return extractZip(res.files.first.path!);
  }

  /// Pilih folder ('Sent Folder') dan imbas semua subfolder.
  Future<MediaPickResult> pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih folder media',
    );
    if (dirPath == null) return const MediaPickResult(items: []);
    return scanFolder(dirPath);
  }

  // ----------------------------------------------------------- scanning

  /// Imbas folder secara rekursif dan kumpulkan semua media.
  MediaPickResult scanFolder(String rootPath) {
    final found = <File>[];
    try {
      final dir = Directory(rootPath);
      if (!dir.existsSync()) {
        return const MediaPickResult(items: [], info: 'Folder tidak dijumpai');
      }
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final e in entities) {
        if (e is File && MediaCatalog.isSupported(e.uri.pathSegments.last)) {
          found.add(e);
        }
      }
    } catch (err) {
      return MediaPickResult(items: const [], info: 'Gagal mengimbas folder: $err');
    }
    found.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return _validate(found.map(_fromFile).toList());
  }

  /// Ekstrak ZIP ke folder sementara dan pulangkan senarai media di dalamnya.
  Future<MediaPickResult> extractZip(String zipPath) async {
    final zf = File(zipPath);
    if (!zf.existsSync()) {
      return const MediaPickResult(items: [], info: 'Fail ZIP tidak dijumpai');
    }
    if (zf.lengthSync() > AppLimits.maxZipBytes) {
      return const MediaPickResult(
          items: [], info: 'Fail ZIP melebihi had 1 GB dan dilangkau');
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
            items: [], info: 'Tiada fail media di dalam ZIP ini');
      }
      return _validate(extracted.map(_fromFile).toList(),
          context: 'ZIP: ${zipPath.split('/').last}');
    } catch (err) {
      return MediaPickResult(items: const [], info: 'Gagal ekstrak ZIP: $err');
    }
  }

  // -------------------------------------------------------- validation

  MediaFile _fromPlatform(PlatformFile f) => MediaFile(
        path: f.path ?? '',
        name: f.name,
        sizeBytes: f.size,
      );

  MediaFile _fromFile(File f) => MediaFile(
        path: f.path,
        name: f.uri.pathSegments.last,
        sizeBytes: f.lengthSync(),
      );

  MediaPickResult _validate(List<MediaFile> files, {String? context}) {
    final items = <MediaItem>[];
    final skipped = <String>[];

    for (final f in files) {
      if (items.length >= AppLimits.maxFiles) {
        skipped.add('${f.name} — melebihi had ${AppLimits.maxFiles} fail');
        continue;
      }
      if (f.path.isEmpty || !File(f.path).existsSync()) {
        skipped.add('${f.name} — fail tidak dijumpai');
        continue;
      }
      if (!MediaCatalog.isSupported(f.name)) {
        skipped.add('${f.name} — jenis fail tidak disokong');
        continue;
      }
      final isImage = MediaCatalog.isImage(f.name);
      final limit = isImage ? AppLimits.maxImageBytes : AppLimits.maxVideoBytes;
      if (f.sizeBytes > limit) {
        final limitLabel = isImage ? '25 MB (gambar)' : '1 GB (video)';
        items.add(_item(f, MediaStatus.oversized, 'Melebihi had $limitLabel'));
        skipped.add('${f.name} — melebihi had $limitLabel');
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

  MediaItem _item(MediaFile f, MediaStatus status, String? note) {
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
