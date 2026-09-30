import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/constants.dart';
import '../core/security.dart';
import '../core/secure_store.dart';
import '../models/models.dart';
import 'database_service.dart';
import 'discord_api.dart';
import 'media_service.dart';
import 'upload_engine.dart';

/// 2a: titik masuk task isolate — WAJIB fungsi top-level dgn pragma.
/// setTaskHandler (dalaman plugin) turut memastikan pendaftaran plugin;
/// panggilan eksplisit dikekalkan sebagai jaminan tambahan.
@pragma('vm:entry-point')
void uploadTaskCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(UploadTaskHandler());
}

/// Notifikasi sesi hantaran (ditulis oleh task isolate sendiri, 2e).
const String kUploadNotificationTitle = 'Sending media to Discord';

/// Teras logik task isolate — TANPA panggilan plugin terus supaya boleh
/// diuji unit dgn enjin/DB palsu (lihat TESTS 2e/2c). Semua komunikasi ke
/// luar melalui callback [sendEvent], [updateNotification], [stopService].
class UploadTaskCore {
  UploadTaskCore({
    UploadEngine? engine,
    DatabaseService? db,
    void Function(Object data)? sendEvent,
    void Function(String title, String text)? updateNotification,
    Future<void> Function()? stopService,
    Future<SendConfig?> Function()? configLoader,
  })  : _engine = engine ?? UploadEngine(api: DiscordApi()),
        _db = db ?? DatabaseService.instance,
        _sendEvent = sendEvent ?? ((_) {}),
        _updateNotification = updateNotification ?? ((_, _) {}),
        _stopService = stopService ?? (() async {}),
        _configLoader = configLoader ?? _defaultConfigLoader {
    _progressSub = _engine.progressStream.listen(_onProgress);
  }

  final UploadEngine _engine;
  final DatabaseService _db;
  final void Function(Object data) _sendEvent;
  final void Function(String title, String text) _updateNotification;
  final Future<void> Function() _stopService;
  final Future<SendConfig?> Function() _configLoader;

  StreamSubscription<UploadProgress>? _progressSub;
  Timer? _heartbeat;
  int? _sessionId;
  bool _starting = false;
  bool _cancelFromNotification = false;
  int _filesDone = 0;
  int _filesTotal = 0;

  /// 2d: sesi ini disambung semula selepas proses terputus — sebab akhir
  /// mesti menyatakan batch dalam penerbangan mungkin terhantar dua kali.
  bool _resumed = false;

  /// 2c: buffer log respons (cincin) — dihantar semula semasa attach.
  final List<ResponseLogEntry> _logBuffer = [];
  int _lastProgressSentMs = 0;
  EngineState? _lastPushedState;

  UploadEngine get engine => _engine;
  int? get activeSessionId => _sessionId;
  bool get isBusy => _engine.isBusy;

  // ------------------------------------------------------------ kitaran

  /// onStart task: sambung semula AUTOMATIK jika proses terputus semasa
  /// sesi berjalan (tetapan sambung semula tersimpan dalam stor selamat
  /// oleh handleStart sendiri). Jika tidak — laporkan status (reattach).
  Future<void> onTaskStart() async {
    try {
      final resume = await SecureStore.loadResumeSettings();
      if (resume.sessionId != null && !_engine.isBusy) {
        final running = await _db.runningSession();
        final pending = await _db.pendingFileCount(resume.sessionId!);
        if (running?.id == resume.sessionId && pending > 0) {
          await handleStart({
            'sessionId': resume.sessionId,
            'maxBatchBytes': resume.maxFileMB * 1024 * 1024,
            'caption': resume.caption,
          });
          return;
        }
      }
    } catch (_) {}
    await sendStatus();
  }

  /// onDestroy: denyar dihentikan — baris DB kekal sebagai sumber
  /// kebenaran; sesi berjalan kekal 'running' (boleh disambung semula, 2d).
  Future<void> onTaskDestroy() async {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  // ------------------------------------------------------------ arahan

  /// Lalui satu arahan daripada main isolate (TaskHandler.onReceiveData).
  /// Dilindungi penuh: ralat apa pun tidak boleh menjadi pengecualian
  /// tak dikendali dalam task isolate.
  Future<void> handleCommand(Object data) async {
    try {
      if (data is! Map) return;
      final cmd = data['cmd'];
      switch (cmd) {
        case 'start':
          await handleStart(Map<String, dynamic>.from(data));
          break;
        case 'cancel':
          await handleCancel(fromNotification: false);
          break;
        case 'pause':
          _engine.pause();
          break;
        case 'resume':
          _engine.resume();
          break;
        case 'status':
          await sendStatus();
          break;
      }
    } catch (e) {
      _sendEvent({
        'event': 'startRejected',
        'sessionId': data is Map ? data['sessionId'] : null,
        'reason': Security.sanitizeText('Unexpected error: $e'),
      });
    }
  }

  /// Mula (atau sambung semula) enjin untuk [cmd['sessionId']]. Baris
  /// PENDING sahaja dihantar — baris 'sent' tidak pernah dihantar semula.
  Future<void> handleStart(Map<String, dynamic> cmd) async {
    if (_starting || _engine.isBusy) {
      _sendEvent({
        'event': 'startRejected',
        'sessionId': cmd['sessionId'],
        'reason': 'A send is already running',
      });
      return;
    }
    _starting = true;
    try {
      final sessionId = (cmd['sessionId'] as num?)?.toInt();
      if (sessionId == null) return;

      // 2e: pengaman sesi tunggal di task isolate — sesi 'running' pada DB
      // mesti sama dengan yang diminta.
      final running = await _db.runningSession();
      if (running?.id != sessionId) {
        _sendEvent({
          'event': 'startRejected',
          'sessionId': sessionId,
          'reason': 'Session is not active',
        });
        return;
      }

      final pending = await _db.pendingSessionFiles(sessionId);
      if (pending.isEmpty) {
        // Sesi terganggu tepat di penghujung — tiada apa-apa lagi untuk
        // dihantar: tamatkan berdasarkan kiraan baris (sumber kebenaran).
        await _finalize(sessionId, engineStatus: null);
        return;
      }

      // 2a: rahsia dibaca DALAM task isolate daripada storan selamat.
      final config = await _configLoader();
      if (config == null || !config.readyToSend) {
        _sendEvent({
          'event': 'startRejected',
          'sessionId': sessionId,
          'reason': 'Configuration is incomplete',
        });
        return;
      }

      // 2d: sambung semula → guna tetapan larian asal (tersimpan dalam
      // stor selamat, bukan rahsia). Mula baharu → arahan membawa nilai.
      final resume = await SecureStore.loadResumeSettings();
      final cmdMaxBytes = (cmd['maxBatchBytes'] as num?)?.toInt() ?? 0;
      final maxBatchBytes = cmdMaxBytes > 0
          ? cmdMaxBytes
          : resume.maxFileMB * 1024 * 1024;
      final cmdCaption = (cmd['caption'] ?? '') as String;
      final caption = cmdCaption.isNotEmpty ? cmdCaption : resume.caption;
      _filesTotal = pending.length;

      // 2d: tanda sambung semula jika sudah ada baris yang diproses.
      final counts = await _db.sessionFileStatusCounts(sessionId);
      _resumed = ((counts['sent'] ?? 0) + (counts['failed'] ?? 0)) > 0;
      _sessionId = sessionId;
      _cancelFromNotification = false;

      // Tetapan sambung semula (bukan rahsia) — digunakan onStart selepas
      // proses mati supaya hantaran diteruskan tanpa UI.
      await SecureStore.saveResumeSettings(
        sessionId: sessionId,
        maxFileMB: maxBatchBytes ~/ (1024 * 1024),
        caption: caption,
      );

      _startHeartbeat();
      _updateNotification(
          kUploadNotificationTitle, 'Preparing ${pending.length} files...');
      _sendEvent({
        'event': 'startAccepted',
        'sessionId': sessionId,
        'totalFiles': pending.length,
        'resumed': _resumed,
      });

      unawaited(_run(
        sessionId: sessionId,
        items: [for (final r in pending) r.toMediaItem()],
        config: config,
        caption: caption,
        maxBatchBytes: maxBatchBytes,
      ));
    } finally {
      _starting = false;
    }
  }

  /// 2e: BATAL — dari app (arahan) atau notifikasi (butang Stop).
  Future<void> handleCancel({required bool fromNotification}) async {
    if (fromNotification) _cancelFromNotification = true;
    if (!_engine.isBusy) {
      // Enjin sudah mati — laporkan status supaya UI pulih sendiri.
      await sendStatus();
      return;
    }
    await _engine.cancel();
  }

  /// 2c: laporkan status semasa (reattach) + buffer log.
  Future<void> sendStatus() async {
    final sessionId = _sessionId;
    final running = _engine.isBusy && sessionId != null;
    final logs = [for (final e in _logBuffer) e.toJson()];
    if (running) {
      final p = _engine.lastProgress;
      _sendEvent({
        'event': 'status',
        'running': true,
        'sessionId': sessionId,
        'progress': _progressMap(p),
        'logs': logs,
      });
    } else {
      _sendEvent({'event': 'status', 'running': false, 'logs': logs});
    }
  }

  // ------------------------------------------------------------- larian

  Future<void> _run({
    required int sessionId,
    required List<MediaItem> items,
    required SendConfig config,
    required String caption,
    required int maxBatchBytes,
  }) async {
    final status = await _engine.run(
      items: items,
      config: config,
      caption: caption,
      maxBatchBytes: maxBatchBytes,
      onBatchFailed: (batch, batchIndex, httpCode, discordCode, errorMessage) {
        // Dilindungi: kegagalan DB tidak boleh mematikan enjin.
        unawaited(() async {
          try {
            await _db.addFailures([
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
                  mode: config.mode.name,
                  target: config.mode == SendMode.webhook
                      ? Security.maskWebhookUrl(config.webhookUrl)
                      : '#${config.channelName.isEmpty ? config.channelId : config.channelName}',
                  createdAt: DateTime.now(),
                ),
            ]);
            await _db.markSessionFiles(sessionId, batch.map((m) => m.path),
                status: 'failed', error: errorMessage ?? 'Unknown error');
          } catch (_) {}
        }());
      },
      onBatchSucceeded: (batch) {
        unawaited(() async {
          try {
            await _db.deleteFailuresByPaths(batch.map((m) => m.path));
            await _db.markSessionFiles(sessionId, batch.map((m) => m.path),
                status: 'sent');
          } catch (_) {}
        }());
      },
      onForegroundUpdate: (batch, totalBatches, percent) {
        _updateNotification(
          kUploadNotificationTitle,
          'Batch $batch/$totalBatches • $percent% • $_filesDone/$_filesTotal files',
        );
      },
    );
    try {
      await _finalize(sessionId, engineStatus: status);
    } catch (_) {}
  }

  /// Tamatkan sesi — DB adalah sumber kebenaran (2b): kiraan daripada
  /// baris, bukan dari memori enjin (penting untuk sesi disambung semula).
  Future<void> _finalize(int sessionId, {String? engineStatus}) async {
    _heartbeat?.cancel();
    _heartbeat = null;

    Map<String, int> counts = const {};
    try {
      counts = await _db.sessionFileStatusCounts(sessionId);
    } catch (_) {}
    final nSent = counts['sent'] ?? 0;
    final nFailed = counts['failed'] ?? 0;
    final notSent = (counts['pending'] ?? 0);

    // Status akhir daripada baris; batal enjin dihormati.
    final String status;
    if (engineStatus == 'cancelled') {
      status = 'cancelled';
    } else if (nFailed == 0 && notSent == 0) {
      status = 'completed';
    } else if (nFailed == 0) {
      status = 'cancelled'; // baki pending tanpa batal = terputus/dibatalkan
    } else if (nSent == 0) {
      status = 'failed';
    } else {
      status = 'partial';
    }

    // Baki pending → 'skipped' (tidak pernah hilang senyap, boleh dihantar
    // semula dari senarai media/Failed).
    try {
      await _db.skipRemainingSessionFiles(sessionId);
    } catch (_) {}

    // Sebab — 4b: enjin menetapkan bagi setiap status bukan-completed.
    String? reason = _engine.lastReason;
    if (_cancelFromNotification) {
      reason = 'Cancelled by user from the notification.';
    }
    if (_resumed) {
      const note = 'Resumed after the app process was interrupted; the batch '
          'in flight may have been sent twice.';
      reason = (reason == null || reason.isEmpty) ? note : '$note $reason';
    }
    // Fallback: jamin TIADA status bukan-completed ditulis tanpa sebab.
    if ((reason == null || reason.isEmpty) && status != 'completed') {
      reason = 'The session was interrupted and recovered. '
          '$nSent file(s) sent, $nFailed failed, $notSent not sent.';
    }
    // Pertahanan kedua: sebab TIDAK PERNAH mengandungi rahsia (URL webhook,
    // token bot) — dapatkan semula walaupun enjin terlepas (4b/2a).
    if (reason != null) {
      reason = Security.sanitizeText(reason);
    }

    try {
      await _db.finishSession(
        sessionId,
        success: nSent,
        failed: nFailed,
        status: status,
        reason: reason,
      );
    } catch (_) {}

    // Buang tetapan sambung semula — sesi sudah tamat.
    try {
      await SecureStore.clearResumeSettings();
    } catch (_) {}

    // 2d: buang folder sementara ZIP milik sesi yang tamat (kecuali yang
    // masih dipakai sesi 'running' lain).
    try {
      final paths = await _db.sessionFilePaths(sessionId);
      final protectedDirs = MediaService.zipTempDirsFor(
          await _db.runningSessionFilePaths());
      await MediaService.deleteSessionZipTempDirs(paths,
          protectedDirs: protectedDirs);
    } catch (_) {}

    // Notifikasi akhir + hentikan servis selepas tempoh tahanan.
    final prefix = switch (status) {
      'completed' => 'Upload finished',
      'partial' => 'Upload finished with failures',
      'failed' => 'Upload failed',
      _ => 'Upload cancelled',
    };
    _updateNotification(
        kUploadNotificationTitle, '$prefix: $nSent sent, $nFailed failed');
    _sendEvent({
      'event': 'finished',
      'sessionId': sessionId,
      'status': status,
      'success': nSent,
      'failed': nFailed,
    });

    _sessionId = null;
    _cancelFromNotification = false;
    _resumed = false;
    _filesDone = 0;
    _filesTotal = 0;

    Timer(AppLimits.finalNotificationHold, () {
      unawaited(_stopService());
    });
  }

  // ------------------------------------------------------- denyar/progres

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // Denyar SEGERA semasa mula — jangan tunggu tick pertama.
    _touchHeartbeatNow();
    _heartbeat = Timer.periodic(
      const Duration(milliseconds: AppLimits.heartbeatIntervalMs),
      (_) => _touchHeartbeatNow(),
    );
  }

  void _touchHeartbeatNow() {
    final id = _sessionId;
    if (id == null) return;
    unawaited(() async {
      try {
        await _db.touchHeartbeat(id);
      } catch (_) {}
    }());
  }

  Map<String, Object?> _progressMap(UploadProgress p) => {
        'state': p.state.name,
        'totalBatches': p.totalBatches,
        'currentBatch': p.currentBatch,
        'totalFiles': p.totalFiles,
        'successFiles': p.successFiles,
        'failedFiles': p.failedFiles,
        'uploadedBytes': p.uploadedBytes,
        'totalBytes': p.totalBytes,
        'speedMBps': p.speedMBps,
        'message': p.message,
      };

  void _onProgress(UploadProgress p) {
    _filesDone = p.successFiles + p.failedFiles;
    _filesTotal = p.totalFiles;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stateChanged = _lastPushedState != p.state;
    if (!stateChanged && now - _lastProgressSentMs < 200) return;
    _lastProgressSentMs = now;
    _lastPushedState = p.state;
    _sendEvent({'event': 'progress', 'sessionId': _sessionId, ..._progressMap(p)});
  }

  // -------------------------------------------------------------- log API

  /// Dilang oleh pemilik core: hook log DiscordApi (task isolate) — masuk
  /// buffer cincin + diteruskan ke main isolate masa nyata.
  void onApiLog(ResponseLogEntry entry) {
    _logBuffer.add(entry);
    if (_logBuffer.length > AppLimits.responseLogCapacity) {
      _logBuffer.removeRange(0, _logBuffer.length - AppLimits.responseLogCapacity);
    }
    _sendEvent({'event': 'log', 'entry': entry.toJson()});
  }

  // -------------------------------------------------------------- tetapan

  /// Konfigurasi hantaran (MENGANDUNGI RAHSIA — kekal dalam task isolate,
  /// tidak pernah dihantar melalui port).
  static Future<SendConfig?> _defaultConfigLoader() async {
    try {
      final map = await SecureStore.loadConfigSafe();
      return SendConfig.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _heartbeat?.cancel();
    _progressSub?.cancel();
  }
}

/// Pembungkus TaskHandler — nipis; semua logik dalam [UploadTaskCore].
class UploadTaskHandler extends TaskHandler {
  UploadTaskCore? _core;

  /// Boleh diganti dalam ujian widget/telemetry jika diperlukan.
  UploadTaskCore createCore() {
    final api = DiscordApi();
    late final UploadTaskCore core;
    core = UploadTaskCore(
      engine: UploadEngine(api: api),
      sendEvent: (data) {
        try {
          FlutterForegroundTask.sendDataToMain(data);
        } catch (_) {}
      },
      updateNotification: (title, text) {
        try {
          FlutterForegroundTask.updateService(
              notificationTitle: title, notificationText: text);
        } catch (_) {}
      },
      stopService: () async {
        try {
          await FlutterForegroundTask.stopService();
        } catch (_) {}
      },
    );
    // Log respons API (masa nyata + buffer cincin untuk reattach, 2c).
    try {
      api.onLog = core.onApiLog;
    } catch (_) {}
    return core;
  }

  UploadTaskCore get core => _core ??= createCore();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await core.onTaskStart();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await core.onTaskDestroy();
  }

  @override
  void onReceiveData(Object data) {
    unawaited(core.handleCommand(data));
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      unawaited(core.handleCancel(fromNotification: true));
    }
  }

  @override
  void onNotificationPressed() {
    // Badan notifikasi membuka app secara automatik (kelakian plugin).
  }
}
