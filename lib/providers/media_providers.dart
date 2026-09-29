import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';

import '../core/constants.dart';
import '../models/models.dart';
import '../services/media_service.dart';

/// Senarai media yang dipilih (state kekal walaupun skrin diputar).
class MediaListNotifier extends StateNotifier<List<MediaItem>> {
  MediaListNotifier() : super(const []);

  int get readyCount => state.where((m) => m.status.canSend).length;

  /// Tambah item; elak duplikasi ikut laluan; hormat had 5,000 fail.
  void addAll(List<MediaItem> items) {
    if (items.isEmpty) return;
    final existingPaths = state.map((m) => m.path).toSet();
    final merged = <MediaItem>[...state];
    for (final item in items) {
      if (existingPaths.contains(item.path)) continue;
      if (merged.length >= AppLimits.maxFiles) break;
      merged.add(item);
      existingPaths.add(item.path);
    }
    state = merged;
  }

  void remove(String id) {
    state = state.where((m) => m.id != id).toList(growable: false);
  }

  void removePaths(Iterable<String> paths) {
    final s = paths.toSet();
    state = state.where((m) => !s.contains(m.path)).toList(growable: false);
  }

  /// B22: buang item yang sudah 'sent' daripada senarai (tindakan
  /// 'Clear sent' pada zon media).
  void clearSent() {
    state = state.where((m) => m.status != MediaStatus.sent).toList(growable: false);
  }

  void clearAll() => state = const [];

  void markStatusByPath(Iterable<String> paths, MediaStatus status) {
    final s = paths.toSet();
    state = [
      for (final m in state)
        if (s.contains(m.path)) m.copyWith(status: status, note: m.note) else m,
    ];
  }

  /// Tindakan pilih: Media / Folder / ZIP.
  /// B02: had saiz aktif dihantar dari Tetapan (maxFileMB).
  Future<String?> pick(PickAction action, {required int maxFileMB}) async {
    final service = MediaService.instance;
    MediaPickResult res;
    switch (action) {
      case PickAction.files:
        res = await service.pickMediaFiles(maxFileMB: maxFileMB);
        break;
      case PickAction.folder:
        res = await service.pickFolder(maxFileMB: maxFileMB);
        break;
      case PickAction.zip:
        res = await service.pickZip(maxFileMB: maxFileMB);
        break;
    }
    addAll(res.items);
    return _resultMessage(res);
  }

  /// Bina mesej ringkas untuk snackbar — senarai panjang 'skipped'
  /// dirumuskan supaya tidak memenuhi skrin.
  String? _resultMessage(MediaPickResult res) {
    if (res.info != null && res.info!.isNotEmpty) return res.info;
    if (res.skipped.isEmpty) return null;
    if (res.skipped.length <= 3) return res.skipped.join('\n');
    final lagi = res.skipped.length - 3;
    return '${res.skipped.length} files skipped:\n'
        '${res.skipped.take(3).join('\n')}\n… and $lagi more';
  }
}

enum PickAction { files, folder, zip }

final mediaListProvider =
    StateNotifierProvider<MediaListNotifier, List<MediaItem>>((ref) => MediaListNotifier());

/// True semasa dialog pilih / imbasan folder / ekstrak ZIP sedang berjalan.
/// Digunakan untuk memaparkan penunjuk 'Mengimbas…' serta-merta dan
/// melumpuhkan butang pilih supaya tidak ditekan dua kali.
final mediaScanBusyProvider = StateProvider<bool>((ref) => false);

/// Kapsyen pilihan (maks 2000 aksara).
final captionProvider = StateProvider<String>((ref) => '');

/// Thumbnail video (gambar terus FileImage).
final videoThumbProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, path) async {
  return FlutterVideoThumbnailPlus.thumbnailData(
    video: path,
    imageFormat: ImageFormat.jpeg,
    quality: 55,
    maxHeight: 320,
  );
});
