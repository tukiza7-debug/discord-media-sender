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
/// - emisi progres masa nyata melalui stream
class UploadEngine {
  UploadEngine({DiscordApi? api}) : _api = api ?? DiscordApi.instance;

  final DiscordApi _api;

  StreamController<UploadProgress>? _controller;
  CancelToken? _cancelToken;

  bool _paused = false;
  bool _cancelRequested = false;
  bool _busy = false;

  bool get isBusy => _busy;

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

  // --- larian utama ----------------------------------------------------

  /// Jalankan hantaran. Kembalikan status akhir sesi.
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
    _cancelToken = CancelToken();
    _controller ??= StreamController<UploadProgress>.broadcast();

    final sendable = items.where((m) => m.status.canSend).toList(growable: false);
    final batches = chunkItems(sendable, AppLimits.batchSize);
    final totalFiles = sendable.length;
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

    var successFiles = 0;
    var failedFiles = 0;
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
      var attempt = 0;
      var ok = false;
      int? lastCode;
      int? lastDiscord;
      String? lastMsg;

      while (attempt < AppLimits.maxRetries && !ok && !_cancelRequested) {
        attempt++;
        _push(
          state: EngineState.running,
          currentBatch: b + 1,
          message: 'Sending batch ${b + 1}/${batches.length}'
              '${attempt > 1 ? ' (attempt $attempt)' : ''}',
        );

        final sw = Stopwatch()..start();
        final outcome = await _api.sendBatch(
          config: config,
          files: batch,
          caption: b == 0 ? caption : null,
          cancelToken: _cancelToken,
          batchNumber: b + 1,
          totalBatches: batches.length,
          attempt: attempt,
        );
        sw.stop();
        activeMs += sw.elapsedMilliseconds;

        if (outcome.success) {
          ok = true;
          lastCode = outcome.httpCode;
          break;
        }
        if (outcome.cancelled) {
          wasCancelled = true;
          break;
        }
        lastCode = outcome.httpCode;
        lastDiscord = outcome.discordCode;
        lastMsg = outcome.errorMessage;

        // Backoff eksponensial sebelum cubaan seterusnya (boleh dijeda).
        if (attempt < AppLimits.maxRetries) {
          final waitMs = backoffForAttempt(attempt) * 1000;
          _push(
            state: EngineState.running,
            currentBatch: b + 1,
            message: 'Failed ($lastMsg). Retrying in ${backoffForAttempt(attempt)}s',
          );
          final completed = await interruptibleWait(
            milliseconds: waitMs,
            isPaused: () => _paused,
            isCancelled: () => _cancelRequested,
          );
          if (!completed) {
            if (_cancelRequested) wasCancelled = true;
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
        onBatchFailed(batch, b + 1, lastCode, lastDiscord, lastMsg);
      }

      final speed = activeMs > 0
          ? uploadedBytes / (activeMs / 1000) / (1024 * 1024)
          : 0.0;
      _push(
        state: EngineState.running,
        currentBatch: b + 1,
        successFiles: successFiles,
        failedFiles: failedFiles,
        uploadedBytes: uploadedBytes,
        speedMBps: speed,
        message: ok ? 'Batch ${b + 1}/${batches.length} done' : 'Batch ${b + 1} failed',
      );
      onForegroundUpdate?.call(
        b + 1,
        batches.length,
        totalBytes > 0 ? (uploadedBytes * 100 / totalBytes).round() : 0,
      );
    }

    _busy = false;

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
      state: wasCancelled
          ? EngineState.cancelled
          : (failedFiles > 0 ? EngineState.done : EngineState.done),
      successFiles: successFiles,
      failedFiles: failedFiles,
      uploadedBytes: uploadedBytes,
      message: wasCancelled ? 'Cancelled' : 'Finished',
    );

    _cancelToken = null;
    return status;
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
