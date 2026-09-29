import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/security.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/discord_api.dart';
import '../services/foreground_manager.dart';
import '../services/upload_engine.dart';
import 'history_providers.dart';
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
  UploadController(this._ref, {UploadEngine? engine})
      : super(const UploadUiState()) {
    _engine = engine ?? UploadEngine(api: DiscordApi.instance);
    // JAMBATAN PROGRES MASA NYATA:
    // Enjin memancar progres sebaik sahaja hantaran bermula — cermin ke
    // state UI dengan segera. (Dulu: state hanya dikemas kini SELEPAS sesi
    // tamat → kad progres kekal "Batch 0/0", "0/0", 0.0%, tiada animasi.)
    _progressSub = _engine.progressStream.listen(_onEngineProgress);
  }

  final Ref _ref;
  late final UploadEngine _engine;
  StreamSubscription<UploadProgress>? _progressSub;

  UploadEngine get engine => _engine;

  void _onEngineProgress(UploadProgress p) {
    if (!mounted) return;
    state = state.copyWith(progress: p, state: p.state);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<String?> start({
    required List<MediaItem> items,
    required SendConfig config,
    required String caption,
  }) async {
    if (state.isRunning) return 'A send is already running';
    final sendable = items.where((m) => m.status.canSend).toList(growable: false);
    if (sendable.isEmpty) return 'No files are ready to send';
    if (!config.readyToSend) return 'Configuration is incomplete';

    // Kebenaran notifikasi (Android 13+).
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}

    await ForegroundManager.start(
      'Sending media to Discord',
      'Preparing ${sendable.length} files...',
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
      status: 'running',
    ));

    // State awal yang bermakna (bukan 0/0) — enjin akan ambil alih sebaik
    // sahaja ia mula memancar progres.
    state = state.copyWith(
      state: EngineState.running,
      activeSessionId: sessionId,
      progress: UploadProgress(
        state: EngineState.running,
        totalBatches: (sendable.length + AppLimits.batchSize - 1) ~/ AppLimits.batchSize,
        currentBatch: 0,
        totalFiles: sendable.length,
        successFiles: 0,
        failedFiles: 0,
        uploadedBytes: 0,
        totalBytes: sendable.fold<int>(0, (s, f) => s + f.sizeBytes),
        speedMBps: 0,
        message: 'Starting...',
      ),
    );

    // Wayar log respons masa nyata.
    DiscordApi.instance.onLog = (entry) {
      _ref.read(responseLogProvider.notifier).add(entry);
    };

    // Enjin dijamin tidak melempar (ada try/catch dalaman) — tetapi jaga
    // jugakan: apa pun yang berlaku, sesi MESTI ditamatkan dalam DB.
    String status;
    try {
      status = await _engine.run(
        items: sendable,
        config: config,
        caption: caption,
        onLog: (entry) => _ref.read(responseLogProvider.notifier).add(entry),
        onBatchFailed: (batch, batchIndex, httpCode, discordCode, errorMessage) async {
          // Dilindungi sepenuhnya: kegagalan DB TIDAK BOLEH menamatkan
          // sesi hantaran dan tidak boleh menjadi pengecualian tak dikendali.
          try {
            await DatabaseService.instance.addFailures([
              for (final f in batch)
                FailedRecord(
                  sessionId: sessionId,
                  fileName: f.name,
                  filePath: f.path,
                  sizeBytes: f.sizeBytes,
                  batchIndex: batchIndex,
                  httpCode: httpCode,
                  errorMessage: errorMessage ?? 'Unknown error',
                  mode: mode,
                  target: target,
                  createdAt: DateTime.now(),
                ),
            ]);
            // Muat semula senarai Failed SEGERA — kegagalan muncul di tab
            // Failed walaupun sesi masih berjalan (dulu: hanya semak semula
            // selepas sesi tamat, dan jika enjin mati awal, tiada langsung).
            try {
              _ref.read(failedProvider.notifier).load();
            } catch (_) {}
          } catch (_) {}
        },
        onForegroundUpdate: (batch, totalBatches, percent) {
          ForegroundManager.update(
            'Sending media to Discord',
            ForegroundManager.progressText(
              batch: batch,
              totalBatches: totalBatches,
              percent: percent,
            ),
          );
        },
      );
    } catch (_) {
      status = _engine.isCancelRequested ? 'cancelled' : 'failed';
    }

    final successCount = _engine.lastProgress.successFiles;
    final failedCount = _engine.lastProgress.failedFiles;

    // SENTIASA tamatkan rekod sesi (dulu: jika enjin mati di tengah jalan,
    // rekod kekal "running" selamanya dan hanya hilang bila app ditutup).
    try {
      await DatabaseService.instance.finishSession(
        sessionId,
        success: successCount,
        failed: failedCount,
        status: status,
      );
    } catch (_) {}
    try {
      await ForegroundManager.stop();
    } catch (_) {}

    state = state.copyWith(
      state: status == 'cancelled' ? EngineState.cancelled : EngineState.done,
      progress: _engine.lastProgress,
      lastFinishedStatus: status,
      clearSession: true,
    );
    _refreshLists();
    return '${describeStatus(status)}: $successCount succeeded, $failedCount failed';
  }

  void pause() => _engine.pause();
  void resume() => _engine.resume();

  /// Batal sesi semasa — UI dikemas kini SEGERA, dan keadaan zombi
  /// (enjin sudah mati tetapi UI masih "running") dipulihkan automatik.
  Future<void> cancel() async {
    if (!_engine.isBusy) {
      // KEADAAN ZOMBI: kad progres masih tergantung walaupun enjin tidak
      // berjalan (kemalangan lama). Pulihkan tanpa perlu tutup app.
      if (state.isRunning) {
        final id = state.activeSessionId;
        if (id != null) {
          try {
            await DatabaseService.instance.finishSession(
              id,
              success: 0,
              failed: 0,
              status: 'cancelled',
            );
          } catch (_) {}
        }
        try {
          await ForegroundManager.stop();
        } catch (_) {}
        state = state.copyWith(
          state: EngineState.cancelled,
          clearSession: true,
          lastFinishedStatus: 'cancelled',
          progress: state.progress.copyWith(
            state: EngineState.cancelled,
            message: 'Cancelled',
          ),
        );
        _refreshLists();
      }
      return;
    }
    // Tunjukkan "Cancelling..." pada UI dengan segera (dulu: UI terus
    // memaparkan "Sending to Discord" sehingga enjin betul-betul tamat).
    state = state.copyWith(state: EngineState.cancelling);
    await _engine.cancel();
  }

  void _refreshLists() {
    try {
      _ref.read(historyProvider.notifier).load();
      _ref.read(failedProvider.notifier).load();
    } catch (_) {}
  }

  void acknowledgeFinished() {
    if (!state.isRunning) {
      state = state.copyWith(state: EngineState.idle, clearSession: true);
    }
  }

  static String describeStatus(String s) {
    switch (s) {
      case 'completed':
        return 'Completed';
      case 'partial':
        return 'Partially successful';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return s;
    }
  }
}

final uploadControllerProvider =
    StateNotifierProvider<UploadController, UploadUiState>(
        (ref) => UploadController(ref));

/// Format ringkas untuk butang sticky.
String sendButtonLabel(int readyCount) => 'Send ($readyCount files)';

String? describeStatusText(String? s) =>
    s == null ? null : UploadController.describeStatus(s);

String formatProgressPct(double fraction) => formatPercent(fraction);
