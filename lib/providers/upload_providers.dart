import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/security.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/discord_api.dart';
import '../services/foreground_manager.dart';
import '../services/media_service.dart';
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

/// Pengawal hantaran utama — 2a: KLIEN bagi task isolate.
///
/// - Pengeluaran: arahan (start/cancel/pause/status) dihantar ke task
///   isolate servis foreground; event (progress/finished/log) dipetakan ke
///   [UploadUiState]. API awam kekal — skrin tidak berubah.
/// - Ujian/keserasian: jika [engine] disuntik, enjin berjalan dalam main
///   isolate seperti dahulu (jalan semula ujian sedia ada).
class UploadController extends StateNotifier<UploadUiState> {
  UploadController(this._ref, {UploadEngine? engine})
      : super(const UploadUiState()) {
    if (engine != null) {
      _engine = engine;
      _inProcess = true;
      // JAMBATAN PROGRES MASA NYATA (mod enjin dalam proses).
      _progressSub = _engine!.progressStream.listen(_onEngineProgress);
    } else {
      // 2c: terima event daripada task isolate.
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    }
    // B12: wayarkan onLog SEKALI semasa provider dicipta — log uji
    // sambungan (testWebhook/testBot) tidak lagi hilang sebelum hantaran
    // pertama. (Dulu: hanya ditetapkan dalam start().)
    DiscordApi.instance.onLog = (entry) {
      _ref.read(responseLogProvider.notifier).add(entry);
    };
  }

  final Ref _ref;
  UploadEngine? _engine;
  StreamSubscription<UploadProgress>? _progressSub;

  /// B03: pengawal SEGERAK sebelum sebarang await — dua tekan Send yang
  /// hampir serentak tidak lagi melalui dua kali.
  bool _starting = false;

  /// Mod enjin dalam proses (ujian sahaja).
  bool _inProcess = false;

  @visibleForTesting
  bool get isInProcessMode => _inProcess;

  UploadEngine get engine => _engine!;

  void _onEngineProgress(UploadProgress p) {
    if (!mounted) return;
    state = state.copyWith(progress: p, state: p.state);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    if (!_inProcess) {
      try {
        FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
      } catch (_) {}
    }
    try {
      DiscordApi.instance.onLog = null;
    } catch (_) {}
    super.dispose();
  }

  // ------------------------------------------------------------ mula

  Future<SendResult> start({
    required List<MediaItem> items,
    required SendConfig config,
    required String caption,
    int maxFileMB = AppLimits.defaultMaxFileMB,
  }) async {
    // B03: pengawal segerak DI PUNCAK — sebelum sebarang await.
    if (_starting || state.isRunning || (_inProcess && _engine!.isBusy)) {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    }
    _starting = true;
    try {
      if (_inProcess) {
        return await _startGuarded(items, config, caption, maxFileMB);
      }
      return await _startViaTask(items, config, caption, maxFileMB);
    } finally {
      _starting = false;
    }
  }

  /// 2a/2b/2e: mula sesi melalui task isolate — klien hanya mencipta
  /// rekod sesi + giliran tahan-lama, kemudian menghantar arahan.
  Future<SendResult> _startViaTask(
    List<MediaItem> items,
    SendConfig config,
    String caption,
    int maxFileMB,
  ) async {
    // 3g: item 'oversized' DISERTAKAN — task menyemak semula melawan had.
    final sendable = items
        .where((m) => m.status.canSend || m.status == MediaStatus.oversized)
        .toList(growable: false);
    if (sendable.isEmpty) {
      return const SendResult(SendResultKind.rejected, 'No files are ready to send');
    }
    if (!config.readyToSend) {
      return const SendResult(
          SendResultKind.rejected, 'Configuration is incomplete');
    }

    // 2e: pengaman sesi tunggal merentas isolate — servis berjalan
    // bermakna sesi lain sedang dihantar.
    if (await ForegroundManager.isServiceRunning()) {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    }

    // Kebenaran notifikasi (Android 13+).
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}

    // Cipta rekod sesi — DB menolak jika sudah ada sesi 'running'.
    final mode = config.mode.name;
    final target = config.mode == SendMode.webhook
        ? Security.maskWebhookUrl(config.webhookUrl)
        : '#${config.channelName.isEmpty ? config.channelId : config.channelName}';
    final int sessionId;
    try {
      sessionId = await DatabaseService.instance.createSession(SessionRecord(
        startedAt: DateTime.now(),
        endedAt: DateTime.now(),
        mode: mode,
        target: target,
        totalFiles: sendable.length,
        successCount: 0,
        failedCount: 0,
        status: 'running',
      ));
    } on StateError {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    } catch (e) {
      return SendResult(
          SendResultKind.rejected,
          'Could not start: ${Security.sanitizeText(e.toString())}');
    }

    // 2b: baris giliran tahan-lama — cebisan transaksi, UI kekal responsif.
    try {
      await DatabaseService.instance.createSessionFiles(sessionId, sendable);
    } catch (e) {
      try {
        await DatabaseService.instance.finishSession(
          sessionId,
          success: 0,
          failed: 0,
          status: 'failed',
          reason: Security.sanitizeText(
              'Could not create the send queue: ${e.toString()}'),
        );
      } catch (_) {}
      return const SendResult(
          SendResultKind.rejected, 'Could not create the send queue');
    }

    // Notifikasi progres + butang Stop + task isolate enjin.
    var serviceOk = false;
    try {
      serviceOk = await ForegroundManager.start(
        'Sending media to Discord',
        'Preparing ${sendable.length} files...',
      );
    } catch (_) {}

    // Keadaan awal yang bermakna (bukan 0/0) — event task akan mengambil
    // alih sebaik sahaja enjin mula memancar progres.
    state = state.copyWith(
      state: EngineState.running,
      activeSessionId: sessionId,
      progress: UploadProgress(
        state: EngineState.running,
        totalBatches:
            (sendable.length + AppLimits.batchSize - 1) ~/ AppLimits.batchSize,
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

    var commandSent = false;
    try {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'start',
        'sessionId': sessionId,
        'maxBatchBytes': maxFileMB * 1024 * 1024,
        'caption': caption,
      });
      commandSent = true;
    } catch (_) {}

    if (!commandSent && !serviceOk) {
      // Servis DAN arahan gagal — tamatkan sesi dengan jelas (jangan zombi).
      await _failFreshSession(sessionId,
          'The background service could not start. No files were sent.');
      return const SendResult(
          SendResultKind.failed, 'Could not start the background service');
    }
    return const SendResult(
        SendResultKind.success, 'Sending started — progress is shown below');
  }

  Future<void> _failFreshSession(int sessionId, String reason) async {
    try {
      await DatabaseService.instance.finalizeUnsentRows(sessionId);
      await DatabaseService.instance.finishSession(
        sessionId,
        success: 0,
        failed: 0,
        status: 'failed',
        reason: reason,
      );
    } catch (_) {}
    if (!mounted) return;
    state = state.copyWith(
      state: EngineState.done,
      lastFinishedStatus: 'failed',
      lastFinishedKind: SendResultKind.failed,
      progress: state.progress.copyWith(
        state: EngineState.done,
        message: reason,
      ),
      clearSession: true,
    );
    _refreshLists();
  }

  // ------------------------------------------------- enjin dalam proses

  Future<SendResult> _startGuarded(
    List<MediaItem> items,
    SendConfig config,
    String caption,
    int maxFileMB,
  ) async {
    // 3g: item 'oversized' DISERTAKAN — enjin menyemak semula melawan had
    // semasa dan melaporkannya ke Failed jika masih terlalu besar.
    final sendable = items
        .where((m) => m.status.canSend || m.status == MediaStatus.oversized)
        .toList(growable: false);
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
    Object? guardError;
    try {
      status = await _engine!.run(
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
          // 2a: notifikasi kini dikemas kini oleh task isolate; dalam mod
          // dalam proses tiada servis aktif yang perlu dikemas kini.
        },
      );
    } catch (e) {
      status = _engine!.isCancelRequested ? 'cancelled' : 'failed';
      // 4b (laluan 6): kemalangan lapisan pengawal — simpan utk sebab.
      guardError = e;
    }

    // B03: 'already-running' — PULANG SEGERA TANPA KESAN SAMPINGAN
    // (tiada finishSession, tiada stop servis, tiada reset state UI).
    if (status == 'already-running') {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    }

    final successCount = _engine!.lastProgress.successFiles;
    final failedCount = _engine!.lastProgress.failedFiles;

    // 4b: sebab sesi — enjin menetapkan bagi setiap status bukan-completed;
    // fallback menjamin TIADA sesi bukan-completed ditulis tanpa sebab.
    String? reason;
    if (status != 'completed') {
      reason = _engine!.lastReason;
      if (reason == null) {
        final brief = guardError?.toString() ?? 'session ended as $status';
        final cut = brief.length > 200 ? brief.substring(0, 200) : brief;
        reason = Security.sanitizeText('Unexpected error: $cut');
      }
    }

    // SENTIASA tamatkan rekod sesi.
    try {
      await DatabaseService.instance.finishSession(
        sessionId,
        success: successCount,
        failed: failedCount,
        status: status,
        reason: reason,
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
      progress: _engine!.lastProgress,
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

  // ------------------------------------------------------ event task 2c

  void _onTaskData(Object data) {
    if (data is! Map) return;
    try {
      applyTaskEvent(Map<String, dynamic>.from(data));
    } catch (_) {}
  }

  /// Petakan event task isolate ke UploadUiState (2c) — AWAM untuk ujian.
  void applyTaskEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['event']) {
      case 'progress':
        // Medan progres berada di peringkat atas event (disebarkan oleh
        // task core) — tiada sarangan.
        final p = _progressFromMap(e);
        state = state.copyWith(progress: p, state: p.state);
        break;
      case 'startAccepted':
        // Kapsyen sudah dihantar bersama arahan — kosongkan (B13: elak
        // hantar berganda teks lama).
        try {
          _ref.read(captionProvider.notifier).state = '';
        } catch (_) {}
        break;
      case 'startRejected':
        if (state.isRunning) {
          final reason = (e['reason'] ?? 'Task rejected the start') as String;
          final id = (e['sessionId'] as num?)?.toInt() ?? state.activeSessionId;
          if (id != null) {
            unawaited(_failFreshSession(id, Security.sanitizeText(reason)));
          } else {
            state = state.copyWith(
              state: EngineState.idle,
              clearSession: true,
              lastFinishedStatus: 'failed',
              lastFinishedKind: SendResultKind.failed,
            );
          }
        }
        break;
      case 'finished':
        final status = (e['status'] ?? 'completed') as String;
        state = state.copyWith(
          state:
              status == 'cancelled' ? EngineState.cancelled : EngineState.done,
          progress: state.progress.copyWith(
            state:
                status == 'cancelled' ? EngineState.cancelled : EngineState.done,
            successFiles: (e['success'] as num?)?.toInt(),
            failedFiles: (e['failed'] as num?)?.toInt(),
            message: describeStatus(status),
          ),
          lastFinishedStatus: status,
          lastFinishedKind: _kindFor(status),
          clearSession: true,
        );
        _refreshLists();
        break;
      case 'status':
        final logs = _logsFrom(e['logs']);
        if (logs.isNotEmpty) {
          _ref.read(responseLogProvider.notifier).addAll(logs);
        }
        if (e['running'] == true) {
          final p = _progressFromMap(
              Map<String, dynamic>.from((e['progress'] ?? const {}) as Map));
          final id = (e['sessionId'] as num?)?.toInt();
          state = state.copyWith(
            state: p.state == EngineState.running
                ? EngineState.running
                : p.state,
            progress: p,
            activeSessionId: id,
          );
        } else if (state.isRunning) {
          // Servis hidup tetapi task tiada sesi — pulihkan UI sahaja
          // (DB kekal sumber kebenaran; healStale/prompt menangani sesi).
          state = state.copyWith(
            state: EngineState.idle,
            progress: state.progress.copyWith(
              state: EngineState.idle,
              message: 'No active session',
            ),
          );
        }
        break;
      case 'log':
        final entry = _logFrom(e['entry']);
        if (entry != null) _ref.read(responseLogProvider.notifier).add(entry);
        break;
      case 'logs':
        final logs = _logsFrom(e['entries']);
        if (logs.isNotEmpty) _ref.read(responseLogProvider.notifier).addAll(logs);
        break;
    }
  }

  UploadProgress _progressFromMap(Map<String, dynamic> m) {
    const fallback = UploadProgress(
      state: EngineState.running,
      totalBatches: 0,
      currentBatch: 0,
      totalFiles: 0,
      successFiles: 0,
      failedFiles: 0,
      uploadedBytes: 0,
      totalBytes: 0,
      speedMBps: 0,
    );
    final stateName = (m['state'] ?? 'running') as String;
    final es = EngineState.values.firstWhere(
      (s) => s.name == stateName,
      orElse: () => EngineState.running,
    );
    return UploadProgress(
      state: es,
      totalBatches: (m['totalBatches'] as num?)?.toInt() ?? fallback.totalBatches,
      currentBatch: (m['currentBatch'] as num?)?.toInt() ?? 0,
      totalFiles: (m['totalFiles'] as num?)?.toInt() ?? 0,
      successFiles: (m['successFiles'] as num?)?.toInt() ?? 0,
      failedFiles: (m['failedFiles'] as num?)?.toInt() ?? 0,
      uploadedBytes: (m['uploadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
      speedMBps: ((m['speedMBps'] ?? 0) as num).toDouble(),
      message: m['message'] as String?,
    );
  }

  ResponseLogEntry? _logFrom(Object? raw) {
    if (raw is Map) {
      try {
        return ResponseLogEntry.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {}
    }
    return null;
  }

  List<ResponseLogEntry> _logsFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <ResponseLogEntry>[];
    for (final item in raw) {
      final entry = _logFrom(item);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  // --------------------------------------------------- kawalan sesi

  void pause() {
    if (_inProcess) {
      _engine?.pause();
      return;
    }
    try {
      FlutterForegroundTask.sendDataToTask({'cmd': 'pause'});
    } catch (_) {}
  }

  void resume() {
    if (_inProcess) {
      _engine?.resume();
      return;
    }
    try {
      FlutterForegroundTask.sendDataToTask({'cmd': 'resume'});
    } catch (_) {}
  }

  /// Batal sesi semasa — UI dikemas kini SEGERA, dan keadaan zombi
  /// (servis/enjin sudah mati tetapi UI masih "running") dipulihkan.
  Future<void> cancel() async {
    if (_inProcess) {
      if (_engine?.isBusy != true) return;
      state = state.copyWith(state: EngineState.cancelling);
      await _engine!.cancel();
      return;
    }
    if (!state.isRunning) return;
    state = state.copyWith(state: EngineState.cancelling);
    if (await ForegroundManager.isServiceRunning()) {
      try {
        FlutterForegroundTask.sendDataToTask({'cmd': 'cancel'});
      } catch (_) {
        await _recoverZombieSession();
      }
    } else {
      await _recoverZombieSession();
    }
  }

  /// KEADAAN ZOMBI: UI masih "running" tetapi servis sudah mati —
  /// tamatkan sesi dgn sebab pemulihan + buang folder sementara (2d).
  Future<void> _recoverZombieSession() async {
    final id = state.activeSessionId;
    if (id != null) {
      try {
        await DatabaseService.instance.finalizeUnsentRows(id);
        final counts =
            await DatabaseService.instance.sessionFileStatusCounts(id);
        await DatabaseService.instance.finishSession(
          id,
          success: counts['sent'] ?? 0,
          failed: counts['failed'] ?? 0,
          status: 'cancelled',
          reason: 'Cancelled by user. The session had stopped unexpectedly '
              'and was recovered; file counts may be incomplete.',
        );
        final paths = await DatabaseService.instance.sessionFilePaths(id);
        final protectedDirs = MediaService.zipTempDirsFor(
            await DatabaseService.instance.runningSessionFilePaths());
        await MediaService.deleteSessionZipTempDirs(paths,
            protectedDirs: protectedDirs);
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

  // -------------------------------------------- sambung semula / buang 2d

  /// 2c: semak semula sesi yang boleh disambung semula (app mula / app
  /// resume). Mengembalikan senarai sesi 'running' yang MATI (servis tidak
  /// berjalan + denyar basi) dan masih ada baris pending.
  Future<List<ResumableSession>> checkResumableSessions() async {
    if (_inProcess) return const [];
    try {
      final alive = await ForegroundManager.isServiceRunning();
      return await DatabaseService.instance.healStaleSessions(serviceAlive: alive);
    } catch (_) {
      return const [];
    }
  }

  /// 2c: reattach — jika servis berjalan dgn sesi aktif, minta statusnya
  /// supaya UI menunjukkan progres semula selepas app dibuka semula.
  Future<void> reattach() async {
    if (_inProcess || state.isRunning) return;
    if (await ForegroundManager.isServiceRunning()) {
      try {
        FlutterForegroundTask.sendDataToTask({'cmd': 'status'});
      } catch (_) {}
    }
  }

  /// 2d: Sambung — mulakan semula servis dan teruskan baris pending
  /// SAHAJA (task membaca giliran dari DB).
  Future<SendResult> resumeSession(int sessionId) async {
    if (_starting || state.isRunning) {
      return const SendResult(
          SendResultKind.rejected, 'A send is already running');
    }
    _starting = true;
    try {
      final pending = await DatabaseService.instance.pendingFileCount(sessionId);
      if (pending <= 0) {
        return const SendResult(SendResultKind.rejected, 'Nothing to resume');
      }
      // Kebenaran notifikasi (Android 13+).
      try {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}

      var serviceOk = false;
      try {
        serviceOk = await ForegroundManager.start(
          'Sending media to Discord',
          'Resuming $pending files...',
        );
      } catch (_) {}

      state = state.copyWith(
        state: EngineState.running,
        activeSessionId: sessionId,
        progress: UploadProgress(
          state: EngineState.running,
          totalBatches: (pending + AppLimits.batchSize - 1) ~/ AppLimits.batchSize,
          currentBatch: 0,
          totalFiles: pending,
          successFiles: 0,
          failedFiles: 0,
          uploadedBytes: 0,
          totalBytes: 0,
          speedMBps: 0,
          message: 'Resuming...',
        ),
      );

      var commandSent = false;
      try {
        // maxBatchBytes/caption = 0 → task guna tetapan sambung semula
        // yang tersimpan (bukan rahsia) dari larian asal.
        FlutterForegroundTask.sendDataToTask({
          'cmd': 'start',
          'sessionId': sessionId,
          'maxBatchBytes': 0,
          'caption': '',
        });
        commandSent = true;
      } catch (_) {}

      if (!commandSent && !serviceOk) {
        state = state.copyWith(
          state: EngineState.idle,
          progress: state.progress.copyWith(
            state: EngineState.idle,
            message: 'Could not resume',
          ),
          clearSession: true,
        );
        return const SendResult(
            SendResultKind.failed, 'Could not start the background service');
      }
      return const SendResult(
          SendResultKind.success, 'Resuming — progress is shown below');
    } finally {
      _starting = false;
    }
  }

  /// 2d: Buang — tamatkan sesi terputus sebagai 'cancelled' dgn sebab
  /// jelas + tanda baki pending sebagai skipped + buang folder sementara.
  Future<void> discardResumable(int sessionId) async {
    try {
      final notSent =
          await DatabaseService.instance.finalizeUnsentRows(sessionId);
      final counts =
          await DatabaseService.instance.sessionFileStatusCounts(sessionId);
      await DatabaseService.instance.finishSession(
        sessionId,
        success: counts['sent'] ?? 0,
        failed: counts['failed'] ?? 0,
        status: 'cancelled',
        reason: 'The app was closed or stopped while this session was '
            'running. It was not cancelled by the user. $notSent file(s) '
            'were not sent.',
      );
      final paths = await DatabaseService.instance.sessionFilePaths(sessionId);
      final protectedDirs = MediaService.zipTempDirsFor(
          await DatabaseService.instance.runningSessionFilePaths());
      await MediaService.deleteSessionZipTempDirs(paths,
          protectedDirs: protectedDirs);
    } catch (_) {}
    _refreshLists();
  }

  // ------------------------------------------------------------ bantu

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

/// 2d: sesi yang menunggu keputusan pengguna (Resume / Discard).
final resumableSessionsProvider =
    StateProvider<List<ResumableSession>>((ref) => const []);

/// Format ringkas untuk butang sticky.
String sendButtonLabel(int readyCount) => 'Send ($readyCount files)';

String? describeStatusText(String? s) =>
    s == null ? null : UploadController.describeStatus(s);

String formatProgressPct(double fraction) => formatPercent(fraction);
