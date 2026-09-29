import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Pengurus foreground service — supaya hantaran tidak dihentikan
/// sistem semasa aplikasi di latar belakang, dan notifikasi progres
/// sentiasa dipaparkan.
///
/// B15: `_running` KINI DISINKRONKAN dengan keadaan servis sebenar
/// (FlutterForegroundTask.isRunningService) sebelum start/stop — dulu ia
/// flag setempat yang tidak pernah direkonsiliasi (contoh: app digesap
/// keluar dari recents → enjin mati tetapi flag masih 'true').
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

  /// B15: selaraskan flag tempatan dengan keadaan servis sebenar.
  /// Gagal (platform tidak sedia, ujian) diabaikan — flag kekal.
  static Future<void> _reconcile() async {
    try {
      final real = await FlutterForegroundTask.isRunningService;
      if (real != _running) _running = real;
    } catch (_) {}
  }

  static Future<void> start(String title, String text) async {
    await _reconcile();
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
    await _reconcile();
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
