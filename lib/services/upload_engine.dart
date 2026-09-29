import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/constants.dart';
import '../models/models.dart';
import 'discord_api.dart';
import 'foreground_manager.dart';

/// Callback bagi kegagalan akhir satu batch (selepas 3 cubaan).
typedef OnBatchFailed = void Function(
  List<MediaItem> batch,
  int batchIndex,
  int? httpCode,
  int? discordCode,
  String? errorMessage,
);

/// Callback kemas kini notifikasi foreground.
typedef OnForegroundUpdate = void Function(int batch, int totalBatches, int percent);

/// Enjin hantaran pukal:
/// - kelompok 10 fail/mesej (had Discord)
/// - auto-retry 3 kali dengan backoff eksponensial
/// - hormati 429 (Retry-After) melalui DiscordApi
/// - Jeda / Sambung / Batal pada bila-bila masa
/// - emisi progres masa nyata melalui stream (per bait, ditebat)
/// - PENGAWAL MASA LUAR: percubaan gantung/tersadai dimatikan sendiri —
///   sesi TIDAK PERNAH tergantung selamanya lagi
/// - run() TIDAK PERNAH melempar pengecualian: kemalangan apa pun menjadi
///   status 'failed'/'cancelled' supaya sesi sentiasa ditamatkan dengan
///   betul dalam sejarah (tiada lagi zombi "running" selepas app ditutup)
class UploadEngine {
  UploadEngine({
    DiscordApi? api,
    this.attemptTimeout = AppLimits.batchAttemptTimeout,
    this.stallTimeout = AppLimits.uploadStallTimeout,
    this.maxRetries = AppLimits.maxRetries,
    List<int>? backoffSeconds,
    this.watchdogTick = const Duration(seconds: 2),
  })  : _api = api ?? DiscordApi.instance,
        backoffSeconds = backoffSeconds ?? AppLimits.retryBackoffSeconds;

  final DiscordApi _api;

  /// Masa luar maksimum SATU percubaan batch (pengawal masa luar).
  final Duration attemptTimeout;

  /// Muat naik dianggap tersadai jika tiada bait terhantar dalam tempoh ini.
  final Duration stallTimeout;

  /// Bilangan percubaan maksimum per batch.
  final int maxRetries;

  /// Backoff antara percubaan (saat) — boleh diganti dalam ujian.
  final List<int> backoffSeconds;

  /// Kekerapan pemeriksaan pengawal masa (kecilkan dalam ujian).
  final Duration watchdogTick;

  StreamController<UploadProgress>? _controller;
  CancelToken? _cancelToken;

  bool _paused = false;
  bool _cancelRequested = false;
  bool _busy = false;

  // Penjejak aktiviti percubaan semasa (digunakan pengawal masa luar).
  bool _attemptUploading = false; // false = fasa tunggu respons / selesai
  DateTime _attemptStart = DateTime.now();
  DateTime _lastActivity = DateTime.now();
  bool _watchdogFired = false;
  DateTime _lastLivePush = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isBusy => _busy;

  bool get isCancelRequested => _cancelRequested;

  // --- kawalan -------------------------------------------------------

  void pause() {
    if (!_busy) return;
    _paused = true;
    _push(state: EngineState.paused, message: 'Paused');
  }

  void resume() {
    if (!_busy) return;
    _paused = false;
    _push(state: EngineState.running, message: 'Resumed');
  }

  Future<void> cancel() async {
    if (!_busy) return;
    _cancelRequested = true;
    _paused = false;
    _push(state: EngineState.cancelling, message: 'Cancelling...');
    _cancelToken?.cancel('Cancelled by user');
  }

  // --- emisi progres ---------------------------------------------------

  UploadProgress _last = const UploadProgress(
    state: EngineState.idle,
    totalBatches: 0,
    currentBatch: 0,
    totalFiles: 0,
    successFiles: 0,
    failedFiles: 0,
    uploadedBytes: 0,
    totalBytes: 0,
    speedMBps: 0,
  );

  Stream<UploadProgress> get progressStream =>
      (_controller ??= StreamController<UploadProgress>.broadcast()).stream;

  UploadProgress get lastProgress => _last;

  void _push({EngineState? state, int? currentBatch, int? successFiles,
      int? failedFiles, int? uploadedBytes, double? speedMBps, String? message}) {
    _last = _last.copyWith(
      state: state,
      currentBatch: currentBatch,
      successFiles: successFiles,
      failedFiles: failedFiles,
      uploadedBytes: uploadedBytes,
      speedMBps: speedMBps,
      message: message,
    );
    _controller?.add(_last);
  }

  /// Kemas kini progres hidup semasa muat naik — ditebat supaya UI tidak
  /// dibina beribu- kali sesaat.
  void _pushLive({int? currentBatch, int? uploadedBytes, double? speedMBps,
      String? message, bool finalChunk = false}) {
    final now = DateTime.now();
    if (!finalChunk &&
        now.difference(_lastLivePush) < AppLimits.progressThrottle) {
      return;
    }
    _lastLivePush = now;
    _push(
      state: EngineState.running,
      currentBatch: currentBatch,
      uploadedBytes: uploadedBytes,
      speedMBps: speedMBps,
      message: message,
    );
  }

  static double _liveSpeed(int ms, int bytes) {
    if (ms <= 0) return 0;
    return bytes / (ms / 1000) / (1024 * 1024);
  }

  // --- larian utama ----------------------------------------------------

  /// Jalankan hantaran. Kembalikan status akhir sesi
  /// ('completed'|'partial'|'failed'|'cancelled'|'already-running').
  /// TIDAK PERNAH melempar pengecualian.
  Future<String> run({
    required List<MediaItem> items,
    required SendConfig config,
    String? caption,
    required void Function(ResponseLogEntry entry) onLog,
    required OnBatchFailed onBatchFailed,
    OnForegroundUpdate? onForegroundUpdate,
  }) async {
    if (_busy) return 'already-running';
    _busy = true;
    _paused = false;
    _cancelRequested = false;
    _watchdogFired = false;
    _controller ??= StreamController<UploadProgress>.broadcast();

    String status;
    try {
      status = await _execute(
        items: items,
        config: config,
        caption: caption,
        onLog: onLog,
        onBatchFailed: onBatchFailed,
        onForegroundUpdate: onForegroundUpdate,
      );
    } catch (e, st) {
      // Rangka pengaman: kemalangan tidak dijangka TIDAK boleh meninggalkan
      // sesi zombi. Tamatkan dengan status yang jelas.
      assert(() {
        // ignore: avoid_print
        print('UploadEngine fatal error: $e\n$st');
        return true;
      }());
      status = _cancelRequested ? 'cancelled' : 'failed';
      _push(
        state: status == 'cancelled' ? EngineState.cancelled : EngineState.done,
        message: status == 'cancelled'
            ? 'Cancelled'
            : 'Failed: unexpected error — ${_briefError(e)}',
      );
    } finally {
      _busy = false;
      _cancelToken = null;
    }
    return status;
  }

  Future<String> _execute({
    required List<MediaItem> items,
    required SendConfig config,
    String? caption,
    required void Function(ResponseLogEntry entry) onLog,
    required OnBatchFailed onBatchFailed,
    OnForegroundUpdate? onForegroundUpdate,
  }) async {
    _cancelToken = CancelToken();

    // Pisahkan fail yang benar-benar wujud pada peranti. Fail hilang tidak
    // lagi masuk kelompok (dulu: MultipartFile.fromFile melempar pengecualian
    // dan membunuh enjin secara senyap → sesi zombi "running").
    final wanted = items.where((m) => m.status.canSend).toList(growable: false);
    final sendable = <MediaItem>[];
    final missing = <MediaItem>[];
    for (final m in wanted) {
      if (File(m.path).existsSync()) {
        sendable.add(m);
      } else {
        missing.add(m);
      }
    }

    final batches = chunkItems(sendable, AppLimits.batchSize);
    final totalFiles = sendable.length + missing.length;
    final totalBytes = sendable.fold<int>(0, (s, f) => s + f.sizeBytes);

    _last = UploadProgress(
      state: EngineState.running,
      totalBatches: batches.length,
      currentBatch: 0,
      totalFiles: totalFiles,
      successFiles: 0,
      failedFiles: 0,
      uploadedBytes: 0,
      totalBytes: totalBytes,
      speedMBps: 0,
      message: 'Starting...',
    );
    _controller!.add(_last);

    if (missing.isNotEmpty) {
      onBatchFailed(missing, 0, null, null, 'File not found on device');
      _push(
        failedFiles: missing.length,
        message:
            '${missing.length} file(s) skipped — not found on device',
      );
    }

    var successFiles = 0;
    var failedFiles = missing.length;
    var uploadedBytes = 0;
    var activeMs = 0;
    var wasCancelled = false;

    for (var b = 0; b < batches.length; b++) {
      // Tunggu jika dijeda.
      while (_paused && !_cancelRequested) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (_cancelRequested) {
        wasCancelled = true;
        break;
      }

      final batch = batches[b];
      final batchBytes = batch.fold<int>(0, (s, f) => s + f.sizeBytes);
      final batchBaseBytes = uploadedBytes;
      var attempt = 0;
      var ok = false;
      int? lastCode;
      int? lastDiscord;
      String? lastMsg;

      while (attempt < maxRetries && !ok && !_cancelRequested) {
        attempt++;
        _push(
          state: EngineState.running,
          currentBatch: b + 1,
          message: 'Sending batch ${b + 1}/${batches.length}'
              '${attempt > 1 ? ' (attempt $attempt)' : ''}',
        );

        // Token BAHARU bagi setiap percubaan: token yang dibatalkan pengawal
        // masa tidak boleh dipakai semula untuk cubaan berikutnya.
        final token = CancelToken();
        _cancelToken = token;

        _attemptStart = DateTime.now();
        _lastActivity = _attemptStart;
        _attemptUploading = true;
        _watchdogFired = false;
        final sw = Stopwatch()..start();

        // PENGAWAL MASA LUAR — mematikan percubaan yang:
        //  (a) tersadai: tiada bait terhantar dalam tempoh [stallTimeout], atau
        //  (b) terlalu lama: melebihi [attemptTimeout] keseluruhan.
        final watchdog = Timer.periodic(watchdogTick, (_) {
          final stalled = _attemptUploading &&
              DateTime.now().difference(_lastActivity) > stallTimeout;
          final tooLong =
              DateTime.now().difference(_attemptStart) > attemptTimeout;
          if (stalled || tooLong) {
            _watchdogFired = true;
            token.cancel('Upload watchdog');
          }
        });

        BatchOutcome outcome;
        try {
          outcome = await _api.sendBatch(
            config: config,
            files: batch,
            caption: b == 0 ? caption : null,
            cancelToken: token,
            batchNumber: b + 1,
            totalBatches: batches.length,
            attempt: attempt,
            onProgress: (sent, total) {
              _lastActivity = DateTime.now();
              // Bait terakhir terhantar → fasa tunggu respons (bukan stall).
              if (total > 0 && sent >= total) _attemptUploading = false;
              _pushLive(
                currentBatch: b + 1,
                uploadedBytes: batchBaseBytes + sent,
                speedMBps: _liveSpeed(sw.elapsedMilliseconds, sent),
                message: 'Sending batch ${b + 1}/${batches.length}'
                    '${attempt > 1 ? ' (attempt $attempt)' : ''}',
                finalChunk: total > 0 && sent >= total,
              );
            },
          );
        } finally {
          watchdog.cancel();
          _attemptUploading = false;
          activeMs += sw.elapsedMilliseconds;
          sw.stop();
        }

        if (outcome.success) {
          ok = true;
          lastCode = outcome.httpCode;
        } else if (outcome.cancelled && _cancelRequested) {
          // Dibatalkan pengguna.
          wasCancelled = true;
        } else if (outcome.cancelled && _watchdogFired) {
          // Dibatalkan PENGAWAL MASA (bukan pengguna) — anggap percubaan
          // gagal dan cuba semula dengan token baharu.
          _watchdogFired = false;
          lastCode = null;
          lastDiscord = null;
          lastMsg = DateTime.now().difference(_attemptStart) > attemptTimeout
              ? 'Attempt timed out (${attemptTimeout.inMinutes} min limit)'
              : 'Upload stalled — no progress for ${stallTimeout.inSeconds}s';
        } else {
          lastCode = outcome.httpCode;
          lastDiscord = outcome.discordCode;
          lastMsg = outcome.errorMessage;
        }

        if (wasCancelled) break;

        // Backoff eksponensial sebelum cubaan seterusnya (boleh dijeda).
        if (!ok && attempt < maxRetries) {
          final waitS =
              backoffSeconds[(attempt - 1).clamp(0, backoffSeconds.length - 1)];
          _push(
            state: EngineState.running,
            currentBatch: b + 1,
            message:
                'Failed${lastMsg == null ? '' : ' ($lastMsg)'}. Retrying in ${waitS}s',
          );
          final completed = await interruptibleWait(
            milliseconds: waitS * 1000,
            isPaused: () => _paused,
            isCancelled: () => _cancelRequested,
          );
          if (!completed && _cancelRequested) {
            wasCancelled = true;
            break;
          }
        }
      }

      if (wasCancelled) break;

      if (ok) {
        successFiles += batch.length;
        uploadedBytes += batchBytes;
      } else {
        failedFiles += batch.length;
        onBatchFailed(batch, b + 1, lastCode, lastDiscord,
            lastMsg ?? 'Unknown error');
      }

      _push(
        state: EngineState.running,
        currentBatch: b + 1,
        successFiles: successFiles,
        failedFiles: failedFiles,
        uploadedBytes: uploadedBytes,
        speedMBps: _liveSpeed(activeMs, uploadedBytes),
        message:
            ok ? 'Batch ${b + 1}/${batches.length} done' : 'Batch ${b + 1} failed',
      );
      onForegroundUpdate?.call(
        b + 1,
        batches.length,
        totalBytes > 0 ? (uploadedBytes * 100 / totalBytes).round() : 0,
      );
    }

    // Status akhir sesi.
    final String status;
    if (wasCancelled) {
      status = 'cancelled';
    } else if (failedFiles == 0) {
      status = 'completed';
    } else if (successFiles == 0) {
      status = 'failed';
    } else {
      status = 'partial';
    }

    _push(
      state: wasCancelled ? EngineState.cancelled : EngineState.done,
      successFiles: successFiles,
      failedFiles: failedFiles,
      uploadedBytes: uploadedBytes,
      message: wasCancelled
          ? 'Cancelled'
          : (status == 'completed'
              ? 'Finished'
              : (status == 'partial'
                  ? 'Finished with failures'
                  : 'Failed')),
    );

    return status;
  }

  static String _briefError(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  static List<List<T>> chunkItems<T>(List<T> list, int size) {
    if (list.isEmpty) return const [];
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      out.add(list.sublist(i, (i + size) > list.length ? list.length : i + size));
    }
    return out;
  }

  /// Semak kewujudan fail sebelum hantar (abaikan yang hilang).
  static List<MediaItem> existingOnly(List<MediaItem> items) => items
      .where((m) => m.status.canSend && File(m.path).existsSync())
      .toList(growable: false);
}
