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
import 'media_providers.dart';
import 'response_providers.dart';

/// B17: jenis keputusan sesi — UI warna/ikon diterbitkan daripada kind.
enum SendResultKind { success, partial, failed, cancelled, rejected }

/// B17: objek keputusan kecil bagi start() — dulu String? menyebabkan
/// snackbar 'A send is already running' dipapar HIJAU (success).
class SendResult {
  const SendResult(this.kind, this.message);
  final SendResultKind kind;
  final String message;

  bool get isGood => kind == SendResultKind.success || kind == SendResultKind.partial;
}

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
    this.lastFinishedKind,
  });

  final EngineState state;
  final UploadProgress progress;
  final int? activeSessionId;
  final String? lastFinishedStatus;
  final SendResultKind? lastFinishedKind;

  bool get isRunning =>
      state == EngineState.running || state == EngineState.paused || state == EngineState.cancelling;

  UploadUiState copyWith({
    EngineState? state,
    UploadProgress? progress,
    int? activeSessionId,
    String? lastFinishedStatus,
    SendResultKind? lastFinishedKind,
    bool clearSession = false,
  }) =>
      UploadUiState(
        state: state ?? this.state,
        progress: progress ?? this.progress,
        activeSessionId: clearSession ? null : (activeSessionId ?? this.activeSessionId),
        lastFinishedStatus: lastFinishedStatus ?? this.lastFinishedStatus,
        lastFinishedKind: lastFinishedKind ?? this.lastFinishedKind,
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
    // state UI dengan segera.
    _progressSub = _engine.progressStream.listen(_onEngineProgress);
    // B12: wayarkan onLog SEKALI semasa provider dicipta — log uji
    // sambungan (testWebhook/testBot) tidak lagi hilang sebelum hantaran
    // pertama. (Dulu: hanya ditetapkan dalam start().)
    DiscordApi.instance.onLog = (entry) {
      _ref.read(responseLogProvider.notifier).add(entry);
    };
  }

  final Ref _ref;
  late final UploadEngine _engine;
  StreamSubscription<UploadProgress>? _progressSub;

  /// B03: pengawal SEGERAK sebelum sebarang await — dua tekan Send yang
  /// hampir serentak tidak lagi melalui dua kali.
  bool _starting = false;

  UploadEngine get engine => _engine;

  void _onEngineProgress(UploadProgress p) {
    if (!mounted) return;
    state = state.copyWith(progress: p, state: p.state);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    try {
      DiscordApi.instance.onLog = null;
    } catch (_) {}
    super.dispose();
  }

  Future<SendResult> start({
    required List<MediaItem> items,
    required SendConfig config,
    required String caption,
    int maxFileMB = AppLimits.defaultMaxFileMB,
  }) async {
    // B03: pengawal segerak DI PUNCAK — sebelum sebarang await.
    if (_starting || state.isRunning || _engine.isBusy) {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    }
    _starting = true;
    try {
      return await _startGuarded(items, config, caption, maxFileMB);
    } finally {
      _starting = false;
    }
  }

  Future<SendResult> _startGuarded(
    List<MediaItem> items,
    SendConfig config,
    String caption,
    int maxFileMB,
  ) async {
    final sendable = items.where((m) => m.status.canSend).toList(growable: false);
    if (sendable.isEmpty) {
      return const SendResult(SendResultKind.rejected, 'No files are ready to send');
    }
    if (!config.readyToSend) {
      return const SendResult(
          SendResultKind.rejected, 'Configuration is incomplete');
    }

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

    // Enjin dijamin tidak melempar (ada try/catch dalaman) — tetapi jaga
    // jugakan: apa pun yang berlaku, sesi MESTI ditamatkan dalam DB.
    String status;
    try {
      status = await _engine.run(
        items: sendable,
        config: config,
        caption: caption,
        maxBatchBytes: maxFileMB * 1024 * 1024,
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
                  discordCode: discordCode,
                  errorMessage: errorMessage ?? 'Unknown error',
                  mode: mode,
                  target: target,
                  createdAt: DateTime.now(),
                ),
            ]);
            // Muat semula senarai Failed SEGERA — kegagalan muncul di tab
            // Failed walaupun sesi masih berjalan.
            try {
              _ref.read(failedProvider.notifier).load();
            } catch (_) {}
          } catch (_) {}
          // B05: tanda item gagal pada senarai media.
          try {
            _ref
                .read(mediaListProvider.notifier)
                .markStatusByPath(batch.map((m) => m.path), MediaStatus.failed);
          } catch (_) {}
        },
        // B04 + B05: batch berjaya — buang rekod gagal lama (retry bersih)
        // dan tanda item sebagai 'sent'.
        onBatchSucceeded: (batch) async {
          try {
            await DatabaseService.instance
                .deleteFailuresByPaths(batch.map((m) => m.path));
            try {
              _ref.read(failedProvider.notifier).load();
            } catch (_) {}
          } catch (_) {}
          try {
            _ref
                .read(mediaListProvider.notifier)
                .markStatusByPath(batch.map((m) => m.path), MediaStatus.sent);
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

    // B03: 'already-running' — PULANG SEGERA TANPA KESAN SAMPINGAN
    // (tiada finishSession, tiada stop servis, tiada reset state UI).
    if (status == 'already-running') {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    }

    final successCount = _engine.lastProgress.successFiles;
    final failedCount = _engine.lastProgress.failedFiles;

    // SENTIASA tamatkan rekod sesi.
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

    // B05: baki fail yang masih 'ready' selepas sesi tamat (pembatalan)
    // ditanda 'cancelled' — masih boleh dihantar semula (canSend).
    if (status == 'cancelled') {
      try {
        final media = _ref.read(mediaListProvider);
        final remaining = media
            .where((m) => m.status == MediaStatus.ready)
            .map((m) => m.path)
            .toList();
        if (remaining.isNotEmpty) {
          _ref
              .read(mediaListProvider.notifier)
              .markStatusByPath(remaining, MediaStatus.cancelled);
        }
      } catch (_) {}
    }

    final kind = _kindFor(status);
    state = state.copyWith(
      state: status == 'cancelled' ? EngineState.cancelled : EngineState.done,
      progress: _engine.lastProgress,
      lastFinishedStatus: status,
      lastFinishedKind: kind,
      clearSession: true,
    );
    _refreshLists();
    return SendResult(
      kind,
      '${describeStatus(status)}: $successCount succeeded, $failedCount failed',
    );
  }

  static SendResultKind _kindFor(String status) {
    switch (status) {
      case 'completed':
        return SendResultKind.success;
      case 'partial':
        return SendResultKind.partial;
      case 'failed':
        return SendResultKind.failed;
      case 'cancelled':
        return SendResultKind.cancelled;
      default:
        return SendResultKind.rejected;
    }
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
          lastFinishedKind: SendResultKind.cancelled,
          progress: state.progress.copyWith(
            state: EngineState.cancelled,
            message: 'Cancelled',
          ),
        );
        _refreshLists();
      }
      return;
    }
    // Tunjukkan "Cancelling..." pada UI dengan segera.
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
