import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/formatters.dart';
import '../core/security.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/discord_api.dart';
import '../services/foreground_manager.dart';
import '../services/upload_engine.dart';
import 'response_providers.dart';

/// Keadaan UI hantaran.
class UploadUiState {
  const UploadUiState({
    this.state = EngineState.idle,
    this.progress = const UploadProgress(
      state: EngineState.idle,
      totalBatches: 0,
      currentBatch: 0,
      totalFiles: 0,
      successFiles: 0,
      failedFiles: 0,
      uploadedBytes: 0,
      totalBytes: 0,
      speedMBps: 0,
    ),
    this.activeSessionId,
    this.lastFinishedStatus,
  });

  final EngineState state;
  final UploadProgress progress;
  final int? activeSessionId;
  final String? lastFinishedStatus;

  bool get isRunning =>
      state == EngineState.running || state == EngineState.paused || state == EngineState.cancelling;

  UploadUiState copyWith({
    EngineState? state,
    UploadProgress? progress,
    int? activeSessionId,
    String? lastFinishedStatus,
    bool clearSession = false,
  }) =>
      UploadUiState(
        state: state ?? this.state,
        progress: progress ?? this.progress,
        activeSessionId: clearSession ? null : (activeSessionId ?? this.activeSessionId),
        lastFinishedStatus: lastFinishedStatus ?? this.lastFinishedStatus,
      );
}

/// Pengawal hantaran utama — menyambung enjin, DB, log respons,
/// notifikasi foreground, dan sejarah.
class UploadController extends StateNotifier<UploadUiState> {
  UploadController(this._ref) : super(const UploadUiState()) {
    _engine = UploadEngine(api: DiscordApi.instance);
  }

  final Ref _ref;
  late final UploadEngine _engine;

  UploadEngine get engine => _engine;

  Future<String?> start({
    required List<MediaItem> items,
    required SendConfig config,
    required String caption,
  }) async {
    if (state.isRunning) return 'Hantaran sedang berjalan';
    final sendable = items.where((m) => m.status.canSend).toList(growable: false);
    if (sendable.isEmpty) return 'Tiada fail sedia untuk dihantar';
    if (!config.readyToSend) return 'Konfigurasi tidak lengkap';

    // Kebenaran notifikasi (Android 13+).
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}

    await ForegroundManager.start(
      'Menghantar media ke Discord',
      'Menyediakan ${sendable.length} fail...',
    );

    // Cipta rekod sesi.
    final mode = config.mode.name;
    final target = config.mode == SendMode.webhook
        ? Security.maskWebhookUrl(config.webhookUrl)
        : '#${config.channelName.isEmpty ? config.channelId : config.channelName}';
    final sessionId = await DatabaseService.instance.createSession(SessionRecord(
      startedAt: DateTime.now(),
      endedAt: DateTime.now(),
      mode: mode,
      target: target,
      totalFiles: sendable.length,
      successCount: 0,
      failedCount: 0,
      status: 'berjalan',
    ));

    state = state.copyWith(state: EngineState.running, activeSessionId: sessionId);

    // Wayar log respons masa nyata.
    DiscordApi.instance.onLog = (entry) {
      _ref.read(responseLogProvider.notifier).add(entry);
    };

    final status = await _engine.run(
      items: sendable,
      config: config,
      caption: caption,
      onLog: (entry) => _ref.read(responseLogProvider.notifier).add(entry),
      onBatchFailed: (batch, batchIndex, httpCode, discordCode, errorMessage) async {
        await DatabaseService.instance.addFailures([
          for (final f in batch)
            FailedRecord(
              sessionId: sessionId,
              fileName: f.name,
              filePath: f.path,
              sizeBytes: f.sizeBytes,
              batchIndex: batchIndex,
              httpCode: httpCode,
              errorMessage: errorMessage ?? 'Ralat tidak diketahui',
              mode: mode,
              target: target,
              createdAt: DateTime.now(),
            ),
        ]);
      },
      onForegroundUpdate: (batch, totalBatches, percent) {
        ForegroundManager.update(
          'Menghantar media ke Discord',
          ForegroundManager.progressText(
            batch: batch,
            totalBatches: totalBatches,
            percent: percent,
          ),
        );
      },
    );

    final successCount = _engine.lastProgress.successFiles;
    final failedCount = _engine.lastProgress.failedFiles;

    await DatabaseService.instance.finishSession(
      sessionId,
      success: successCount,
      failed: failedCount,
      status: status,
    );
    await ForegroundManager.stop();

    // Buang fail yang sudah dihantar daripada senarai kekal yang gagal ditanda.
    state = state.copyWith(
      state: _engine.lastProgress.state,
      progress: _engine.lastProgress,
      lastFinishedStatus: status,
      clearSession: true,
    );
    return '${describeStatus(status)}: $successCount berjaya, $failedCount gagal';
  }

  void pause() => _engine.pause();
  void resume() => _engine.resume();
  Future<void> cancel() => _engine.cancel();

  void acknowledgeFinished() {
    if (!state.isRunning) {
      state = state.copyWith(state: EngineState.idle, clearSession: true);
    }
  }

  static String describeStatus(String s) {
    switch (s) {
      case 'selesai':
        return 'Selesai';
      case 'separa':
        return 'Separa berjaya';
      case 'gagal':
        return 'Gagal';
      case 'dibatalkan':
        return 'Dibatalkan';
      default:
        return s;
    }
  }
}

final uploadControllerProvider =
    StateNotifierProvider<UploadController, UploadUiState>((ref) => UploadController(ref));

/// Format ringkas untuk butang sticky.
String sendButtonLabel(int readyCount) => 'Hantar ($readyCount fail)';

String? describeStatusText(String? s) =>
    s == null ? null : UploadController.describeStatus(s);

String formatProgressPct(double fraction) => formatPercent(fraction);
