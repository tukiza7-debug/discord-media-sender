import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'upload_task_handler.dart';

/// Pengurus foreground service (2a) — enjin hantaran kini berjalan DI
/// DALAM task isolate servis; main isolate hanyalah klien. Servis menahan
/// proses, memaparkan notifikasi progres dgn butang Stop, dan DIRESTASI
/// AUTOMATIK oleh plugin selepas proses mati (RestartReceiver + START_STICKY
/// — disahkan dalam sumber plugin 8.17.0; tiada opsyen allowAutoRestart
/// berasingan pada versi ini).
///
/// B15: `_running` KINI DISINKRONKAN dengan keadaan servis sebenar
/// (FlutterForegroundTask.isRunningService) sebelum start/stop.
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
      // 2e: allowWifiLock — radio Wi-Fi kekal hidup semasa muat naik besar
      // (WAKE_LOCK sudah diisytiharkan dalam manifest).
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// 2c: panggil sekali dalam main() — daftar port komunikasi main isolate.
  static void initCommunicationPort() {
    FlutterForegroundTask.initCommunicationPort();
  }

  /// B15: selaraskan flag tempatan dengan keadaan servis sebenar.
  static Future<void> _reconcile() async {
    _running = await isServiceRunning();
  }

  /// Keadaan servis sebenar (aman untuk dipanggil di mana-mana).
  static Future<bool> isServiceRunning() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  /// Mulakan servis dgn task callback + butang Stop (2e). Kembalikan true
  /// jika servis berjalan (atau sudah berjalan).
  static Future<bool> start(String title, String text) async {
    await _reconcile();
    if (_running) return true;
    final result = await FlutterForegroundTask.startService(
      notificationTitle: title,
      notificationText: text,
      notificationButtons: const [
        NotificationButton(id: 'stop', text: 'Stop'),
      ],
      callback: uploadTaskCallback,
    );
    _running = result is ServiceRequestSuccess;
    return _running;
  }

  static Future<void> stop() async {
    await _reconcile();
    if (!_running) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _running = false;
  }

  static bool get isRunning => _running;
}
