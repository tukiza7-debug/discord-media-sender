import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/constants.dart';

/// Pengurus foreground service — supaya hantaran tidak dihentikan
/// sistem semasa aplikasi di latar belakang, dan notifikasi progres
/// sentiasa dipaparkan.
class ForegroundManager {
  ForegroundManager._();
  static bool _running = false;

  /// Mesti dipanggil sekali dalam main() sebelum runApp.
  static void ensureInit() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'dms_upload_channel',
        channelName: 'Media Uploads',
        channelDescription: 'Shows the progress of media uploads to Discord.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> start(String title, String text) async {
    if (_running) {
      update(title, text);
      return;
    }
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
        // Callback kosong: task handler tidak diperlukan kerana enjin
        // hantaran berjalan dalam main isolate; servis hanya menahan
        // proses supaya tidak dibunuh sistem.
      );
      _running = true;
    } catch (_) {
      // Jika servis gagal bermula (contoh kebenaran notifikasi), hantaran
      // tetap diteruskan — hanya tanpa notifikasi latar belakang.
    }
  }

  static void update(String title, String text) {
    if (!_running) return;
    try {
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_running) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _running = false;
  }

  static bool get isRunning => _running;

  static String progressText(
      {required int batch, required int totalBatches, required int percent}) {
    return 'Batch $batch/$totalBatches • $percent% • Discord Media Sender';
  }
}

/// Pemuat semula kecil util — dikekal untuk jelas (had backoff).
int backoffForAttempt(int attempt) {
  final idx = (attempt - 1).clamp(0, AppLimits.retryBackoffSeconds.length - 1);
  return AppLimits.retryBackoffSeconds[idx];
}

/// Tamat masa tunggu yang boleh dijeda/batalkan (dipakai enjin).
Future<bool> interruptibleWait({
  required int milliseconds,
  required bool Function() isPaused,
  required bool Function() isCancelled,
  Duration step = const Duration(milliseconds: 100),
}) async {
  var waited = 0;
  while (waited < milliseconds) {
    if (isCancelled()) return false;
    if (!isPaused()) waited += step.inMilliseconds;
    await Future<void>.delayed(step);
  }
  return !isCancelled();
}

/// Akses ringkas fail — dikekal untuk utiliti enjin.
bool fileExists(String path) => File(path).existsSync();
