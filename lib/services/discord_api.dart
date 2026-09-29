import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart' as hp;

import '../core/constants.dart';
import '../core/error_translator.dart';
import '../core/security.dart';
import '../models/models.dart';

/// Keputusan satu batch hantaran.
class BatchOutcome {
  const BatchOutcome({
    required this.success,
    this.cancelled = false,
    this.httpCode,
    this.discordCode,
    this.errorMessage,
  });

  final bool success;
  final bool cancelled;
  final int? httpCode;
  final int? discordCode;
  final String? errorMessage;
}

/// Klien API Discord untuk mod Webhook & Bot.
///
/// KESELAMATAN: semua entri log yang dihasilkan di sini sentiasa ditapis —
/// token bot, header Authorization dan URL webhook penuh tidak akan muncul.
class DiscordApi {
  DiscordApi() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      // sendTimeout sengaja ditiadakan — muat naik besar perlu masa;
      // pengawal masa luar (watchdog) diuruskan oleh UploadEngine.
      headers: {'Accept': 'application/json'},
    ));
  }

  static final DiscordApi instance = DiscordApi();

  late final Dio _dio;

  /// Header Authorization sebenar untuk mod Bot.
  /// PUNCA BUG LAMA: Security.maskBotToken() (fungsi TOPEKAN log) pernah
  /// dipakai di sini — header menjadi "Bot ****" → Discord sentiasa 401.
  /// Token sebenar diperlukan pada talian; topengan HANYA untuk log/paparan.
  @visibleForTesting
  static String botAuthHeader(String rawToken) {
    final t = rawToken.trim();
    if (t.isEmpty) return '';
    // Jika pengguna tampal bersama awalan "Bot ", gunakan seperti sedia.
    if (t.toLowerCase().startsWith('bot ')) return t;
    return 'Bot $t';
  }

  /// Hook log masa nyata (diwayar oleh enjin hantaran).
  void Function(ResponseLogEntry entry)? onLog;

  /// Ujian sahaja: ganti adapter Dio (mock 429 dsb. tanpa rangkaian).
  @visibleForTesting
  void debugAttachAdapter(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  // ---------------------------------------------------------------- send

  Future<BatchOutcome> sendBatch({
    required SendConfig config,
    required List<MediaItem> files,
    String? caption,
    CancelToken? cancelToken,
    required int batchNumber,
    required int totalBatches,
    required int attempt,
    void Function(int sent, int total)? onProgress,

    /// Flag batal luaran (enjin) — ditambah pada CancelToken supaya
    /// tunggu rate-limit juga boleh dihentikan.
    bool Function()? isCancelled,

    /// Tick berkala semasa menunggu rate-limit — enjin guna ini untuk
    /// menyegarkan _lastActivity supaya stall watchdog tidak tercetus.
    void Function()? onRateLimitWaitTick,
  }) async {
    final isWebhook = config.mode == SendMode.webhook;
    final endpoint = isWebhook
        ? config.webhookUrl.trim()
        : '${DiscordConstants.apiBase}/channels/${config.channelId.trim()}/messages';
    final maskedEndpoint = isWebhook
        ? Security.maskWebhookUrl(endpoint)
        : endpoint.replaceFirst(DiscordConstants.apiBase, '');

    final payload = <String, dynamic>{};
    final text = caption?.trim() ?? '';
    if (text.isNotEmpty) payload['content'] = text;
    // B18: matikan mentions secara lalai — kapsyen tidak boleh
    // mass-mention @everyone/@here/@role/@user secara tidak sengaja.
    if (!AppLimits.allowCaptionMentions) {
      payload['allowed_mentions'] = const {'parse': <String>[]};
    }
    if (isWebhook) {
      if (config.botName.trim().isNotEmpty) payload['username'] = config.botName.trim();
      if (config.avatarUrl.trim().isNotEmpty) payload['avatar_url'] = config.avatarUrl.trim();
    }
    final uploadBytes = files.fold<int>(0, (s, f) => s + f.sizeBytes);
    final fileNames = files.map((f) => f.name).toList(growable: false);

    var rateWaits = 0;
    while (true) {
      final headers = <String, String>{
        if (!isWebhook) 'Authorization': botAuthHeader(config.botToken),
      };
      final sw = Stopwatch()..start();
      try {
        // Bina form DALAM try — fail yang hilang/tak boleh dibaca menjadi
        // kegagalan batch yang dilaporkan, bukan kemalangan senyap.
        final form = await _buildForm(payload, files);
        final resp = await _dio.post<dynamic>(
          endpoint,
          data: form,
          cancelToken: cancelToken,
          options: Options(headers: headers),
          onSendProgress: (sent, total) => onProgress?.call(sent, total),
        );
        sw.stop();
        _emit(ResponseLogEntry(
          id: _entryId(),
          batchNumber: batchNumber,
          totalBatches: totalBatches,
          fileCount: files.length,
          fileNames: fileNames,
          filePaths: files.map((f) => f.path).toList(growable: false),
          endpoint: maskedEndpoint,
          method: 'POST',
          status: LogStatus.success,
          statusCode: resp.statusCode,
          reasonPhrase: resp.statusMessage ?? 'OK',
          latencyMs: sw.elapsedMilliseconds,
          uploadBytes: uploadBytes,
          speedMBps: _speed(uploadBytes, sw.elapsedMilliseconds),
          attempt: attempt,
          timestamp: DateTime.now(),
          rateLimitHeaders: _rateHeaders(resp.headers.map),
          responseJson: Security.sanitizeJson(resp.data),
        ));
        return BatchOutcome(success: true, httpCode: resp.statusCode);
      } on DioException catch (e) {
        sw.stop();
        if (e.type == DioExceptionType.cancel) {
          _emit(_errorEntry(
            config: config,
            maskedEndpoint: maskedEndpoint,
            fileNames: fileNames,
            filePaths: files.map((f) => f.path).toList(growable: false),
            batchNumber: batchNumber,
            totalBatches: totalBatches,
            uploadBytes: uploadBytes,
            attempt: attempt,
            status: LogStatus.cancelled,
            statusCode: null,
            e: e,
            elapsedMs: sw.elapsedMilliseconds,
            explanationOverride: 'Request cancelled by the user.',
          ));
          return const BatchOutcome(success: false, cancelled: true);
        }

        final code = e.response?.statusCode;
        // Hormati rate limit Discord (HTTP 429 + Retry-After).
        if (code == 429 && rateWaits < AppLimits.maxRateLimitWaits) {
          final waitMs = _retryAfterMs(e.response) ?? 1500;
          _emit(_errorEntry(
            config: config,
            maskedEndpoint: maskedEndpoint,
            fileNames: fileNames,
            filePaths: files.map((f) => f.path).toList(growable: false),
            batchNumber: batchNumber,
            totalBatches: totalBatches,
            uploadBytes: uploadBytes,
            attempt: attempt,
            status: LogStatus.rateLimited,
            statusCode: 429,
            e: e,
            elapsedMs: sw.elapsedMilliseconds,
            retryAfterMs: waitMs,
          ));
          // B01: tunggu BOLEH-BATAL (hormati CancelToken + flag enjin)
          // dan memberi tick supaya stall watchdog tidak tercetus.
          final cancelledDuringWait = await _cancelAwareWait(
            waitMs,
            cancelToken: cancelToken,
            isCancelled: isCancelled,
            onTick: onRateLimitWaitTick,
          );
          if (cancelledDuringWait) {
            _emit(_errorEntry(
              config: config,
              maskedEndpoint: maskedEndpoint,
              fileNames: fileNames,
              filePaths: files.map((f) => f.path).toList(growable: false),
              batchNumber: batchNumber,
              totalBatches: totalBatches,
              uploadBytes: uploadBytes,
              attempt: attempt,
              status: LogStatus.cancelled,
              statusCode: 429,
              e: e,
              elapsedMs: sw.elapsedMilliseconds,
              explanationOverride:
                  'Request cancelled while waiting out the rate limit.',
            ));
            return const BatchOutcome(
                success: false, cancelled: true, httpCode: 429);
          }
          rateWaits++;
          continue;
        }

        final body = e.response?.data;
        final dCode = _discordErrorCode(body);
        final expl = ErrorTranslator.explain(statusCode: code, discordCode: dCode, error: e);
        _emit(_errorEntry(
          config: config,
          maskedEndpoint: maskedEndpoint,
          fileNames: fileNames,
          filePaths: files.map((f) => f.path).toList(growable: false),
          batchNumber: batchNumber,
          totalBatches: totalBatches,
          uploadBytes: uploadBytes,
          attempt: attempt,
          status: code != null && code >= 500
              ? LogStatus.serverError
              : (code != null ? LogStatus.clientError : LogStatus.networkError),
          statusCode: code,
          e: e,
          elapsedMs: sw.elapsedMilliseconds,
          explanationOverride:
              '${expl.title} — ${expl.detail}${dCode != null ? ' (Discord code: $dCode)' : ''}',
        ));
        return BatchOutcome(
          success: false,
          httpCode: code,
          discordCode: dCode,
          errorMessage: expl.title,
        );
      } catch (err) {
        sw.stop();
        final expl = ErrorTranslator.explain(error: err);
        _emit(_errorEntry(
          config: config,
          maskedEndpoint: maskedEndpoint,
          fileNames: fileNames,
          filePaths: files.map((f) => f.path).toList(growable: false),
          batchNumber: batchNumber,
          totalBatches: totalBatches,
          uploadBytes: uploadBytes,
          attempt: attempt,
          status: LogStatus.networkError,
          statusCode: null,
          e: DioException(requestOptions: RequestOptions(path: endpoint), error: err),
          elapsedMs: sw.elapsedMilliseconds,
          explanationOverride: '${expl.title} — ${expl.detail}',
        ));
        return BatchOutcome(success: false, errorMessage: expl.title);
      }
    }
  }

  Future<FormData> _buildForm(Map<String, dynamic> payload, List<MediaItem> files) async {
    final form = FormData();
    if (payload.isNotEmpty) {
      form.fields.add(MapEntry('payload_json', jsonEncodeSafe(payload)));
    }
    for (var i = 0; i < files.length; i++) {
      form.files.add(MapEntry(
        'files[$i]',
        await MultipartFile.fromFile(
          files[i].path,
          filename: files[i].name,
          contentType: hp.MediaType.parse(files[i].mimeType),
        ),
      ));
    }
    return form;
  }

  // ------------------------------------------------------------ testing

  Future<TestResult> testWebhook(String url) async {
    try {
      final resp = await _dio.get<dynamic>(url.trim());
      final name = resp.data is Map ? (resp.data['name']?.toString() ?? '') : '';
      _emit(ResponseLogEntry(
        id: _entryId(),
        batchNumber: 0,
        totalBatches: 0,
        fileCount: 0,
        fileNames: const [],
        filePaths: const [],
        endpoint: Security.maskWebhookUrl(url),
        method: 'GET',
        status: LogStatus.success,
        statusCode: resp.statusCode,
        reasonPhrase: resp.statusMessage ?? 'OK',
        latencyMs: 0,
        uploadBytes: 0,
        speedMBps: 0,
        attempt: 1,
        timestamp: DateTime.now(),
        responseJson: Security.sanitizeJson(resp.data),
      ));
      return TestResult(
          ok: true, message: name.isEmpty ? 'Webhook valid' : 'Webhook valid: $name');
    } on DioException catch (e) {
      return _testError(e, 'Webhook');
    } catch (e) {
      return TestResult(ok: false, message: 'Connection failed: $e');
    }
  }

  Future<TestResult> testBot(String token, String channelId) async {
    try {
      final me = await _dio.get<Map<String, dynamic>>(
        '${DiscordConstants.apiBase}/users/@me',
        options: Options(headers: {'Authorization': botAuthHeader(token)}),
      );
      final botName = me.data?['username']?.toString() ?? 'Bot';
      final ch = await _dio.get<Map<String, dynamic>>(
        '${DiscordConstants.apiBase}/channels/${channelId.trim()}',
        options: Options(headers: {'Authorization': botAuthHeader(token)}),
      );
      final chName = ch.data?['name']?.toString() ?? '';
      _emit(ResponseLogEntry(
        id: _entryId(),
        batchNumber: 0,
        totalBatches: 0,
        fileCount: 0,
        fileNames: const [],
        filePaths: const [],
        endpoint: '${DiscordConstants.apiBase.replaceFirst('https://', '')}/users/@me + /channels',
        method: 'GET',
        status: LogStatus.success,
        statusCode: me.statusCode,
        reasonPhrase: 'OK',
        latencyMs: 0,
        uploadBytes: 0,
        speedMBps: 0,
        attempt: 1,
        timestamp: DateTime.now(),
        responseJson: {'bot': botName, 'channel': chName},
      ));
      return TestResult(ok: true, message: 'Bot valid: $botName • Channel: #$chName');
    } on DioException catch (e) {
      return _testError(e, 'Bot');
    } catch (e) {
      return TestResult(ok: false, message: 'Connection failed: $e');
    }
  }

  TestResult _testError(DioException e, String kind) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final dCode = _discordErrorCode(body);
    final expl = ErrorTranslator.explain(statusCode: code, discordCode: dCode, error: e);
    _emit(ResponseLogEntry(
      id: _entryId(),
      batchNumber: 0,
      totalBatches: 0,
      fileCount: 0,
      fileNames: const [],
      filePaths: const [],
      endpoint: kind == 'Webhook' ? 'webhooks/**** (connection test)' : 'discord.com/api/v10/... (connection test)',
      method: 'GET',
      status: code != null && code >= 500
          ? LogStatus.serverError
          : (code != null ? LogStatus.clientError : LogStatus.networkError),
      statusCode: code,
      reasonPhrase: e.response?.statusMessage,
      latencyMs: 0,
      uploadBytes: 0,
      speedMBps: 0,
      attempt: 1,
      timestamp: DateTime.now(),
      rateLimitHeaders: _rateHeaders(e.response?.headers.map),
      responseJson: Security.sanitizeJson(body is Map ? body : null),
      errorMessage: expl.title,
      explanation: '${expl.title} — ${expl.detail}',
    ));
    return TestResult(ok: false, message: expl.title);
  }

  // ----------------------------------------------------------- channels

  Future<List<GuildInfo>> fetchGuilds(String token) async {
    // B20: pagination — Discord hadkan 100 guild per halaman (after=<id>).
    final out = <GuildInfo>[];
    var after = '0';
    for (var page = 0; page < 10; page++) {
      final resp = await _dio.get<List<dynamic>>(
        '${DiscordConstants.apiBase}/users/@me/guilds?with_counts=false&limit=100&after=$after',
        options: Options(headers: {'Authorization': botAuthHeader(token)}),
      );
      final rows = resp.data ?? [];
      if (rows.isEmpty) break;
      for (final g in rows.whereType<Map<String, dynamic>>()) {
        final id = (g['id'] ?? '').toString();
        out.add(GuildInfo(id: id, name: (g['name'] ?? 'Server').toString()));
        after = id;
      }
      if (rows.length < 100) break;
    }
    return out;
  }

  Future<List<ChannelInfo>> fetchTextChannels(String token, String guildId) async {
    final resp = await _dio.get<List<dynamic>>(
      '${DiscordConstants.apiBase}/guilds/$guildId/channels',
      options: Options(headers: {'Authorization': botAuthHeader(token)}),
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        // type 0 = GUILD_TEXT, type 5 = GUILD_ANNOUNCEMENT (B20)
        .where((c) => (c['type'] ?? -1) == 0 || (c['type'] ?? -1) == 5)
        .map((c) => ChannelInfo(
              id: (c['id'] ?? '').toString(),
              name: (c['name'] ?? '').toString(),
              guildId: guildId,
            ))
        .toList();
  }

  Future<ChannelInfo> createChannel({
    required String token,
    required String guildId,
    required String name,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '${DiscordConstants.apiBase}/guilds/$guildId/channels',
      data: {'name': name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-'), 'type': 0},
      options: Options(headers: {'Authorization': botAuthHeader(token)}),
    );
    final d = resp.data ?? const {};
    return ChannelInfo(
      id: (d['id'] ?? '').toString(),
      name: (d['name'] ?? name).toString(),
      guildId: guildId,
    );
  }

  // ------------------------------------------------------------ helpers

  /// B01: tunggu yang boleh dihentikan — semak CancelToken + flag batal
  /// enjin setiap 100 ms dan panggil onTick supaya enjin boleh menyegarkan
  /// _lastActivity (stall watchdog tidak tercetus semasa tunggu 429).
  /// Pulangkan true jika dibatalkan semasa menunggu.
  Future<bool> _cancelAwareWait(
    int milliseconds, {
    CancelToken? cancelToken,
    bool Function()? isCancelled,
    void Function()? onTick,
  }) async {
    const step = 100;
    var waited = 0;
    while (waited < milliseconds) {
      if (cancelToken?.isCancelled ?? false) return true;
      if (isCancelled?.call() ?? false) return true;
      await Future<void>.delayed(const Duration(milliseconds: step));
      waited += step;
      onTick?.call();
    }
    return false;
  }

  void _emit(ResponseLogEntry entry) {
    final log = onLog;
    if (log != null) log(entry);
  }

  String _entryId() =>
      'e${DateTime.now().microsecondsSinceEpoch}-${(DateTime.now().microsecond % 997)}';

  double _speed(int bytes, int ms) {
    if (ms <= 0) return 0;
    return bytes / (ms / 1000) / (1024 * 1024);
  }

  Map<String, String> _rateHeaders(Map<String, List<String>>? headers) {
    if (headers == null) return const {};
    const keys = [
      'x-ratelimit-remaining',
      'x-ratelimit-reset-after',
      'retry-after',
    ];
    final out = <String, String>{};
    for (final k in keys) {
      final v = headers[k];
      if (v != null && v.isNotEmpty) out[k] = v.first;
    }
    return out;
  }

  int? _retryAfterMs(Response? resp) {
    // B01: 'Retry-After' header (saat, boleh perpuluhan) — diutamakan.
    final h = resp?.headers.value('retry-after');
    if (h != null) {
      final v = double.tryParse(h);
      if (v != null) return _clampRateWait((v * 1000).round());
    }
    // B01: badan 429 Discord — retry_after adalah FLOAT dalam SAAT
    // (dok Discord: "number of seconds to wait"), BUKAN milisaat.
    final body = resp?.data;
    if (body is Map && body['retry_after'] != null) {
      final v = double.tryParse(body['retry_after'].toString());
      if (v != null) return _clampRateWait((v * 1000).round());
    }
    return null;
  }

  /// Kepit tunggu rate-limit ke julat munasabah (250 ms … 10 minit).
  static int _clampRateWait(int ms) =>
      ms.clamp(AppLimits.minRateLimitWaitMs, AppLimits.maxRateLimitWaitMs);

  int? _discordErrorCode(Object? body) {
    if (body is Map && body['code'] != null) {
      return int.tryParse(body['code'].toString());
    }
    return null;
  }

  ResponseLogEntry _errorEntry({
    required SendConfig config,
    required String maskedEndpoint,
    required List<String> fileNames,
    required List<String> filePaths,
    required int batchNumber,
    required int totalBatches,
    required int uploadBytes,
    required int attempt,
    required LogStatus status,
    required int? statusCode,
    required DioException e,
    required int elapsedMs,
    String? explanationOverride,
    int? retryAfterMs,
  }) {
    final code = e.response?.statusCode;
    final body = e.response?.data;
    final dCode = _discordErrorCode(body);
    final expl = ErrorTranslator.explain(statusCode: code, discordCode: dCode, error: e);
    final msg = e.message ?? e.error?.toString() ?? 'Unknown error';
    return ResponseLogEntry(
      id: _entryId(),
      batchNumber: batchNumber,
      totalBatches: totalBatches,
      fileCount: fileNames.length,
      fileNames: fileNames,
      filePaths: filePaths,
      endpoint: maskedEndpoint,
      method: 'POST',
      status: status,
      statusCode: statusCode,
      reasonPhrase: e.response?.statusMessage,
      latencyMs: elapsedMs,
      uploadBytes: uploadBytes,
      speedMBps: _speed(uploadBytes, elapsedMs),
      attempt: attempt,
      timestamp: DateTime.now(),
      rateLimitHeaders: _rateHeaders(e.response?.headers.map),
      responseJson: Security.sanitizeJson(body is Map ? body : null),
      errorMessage: msg,
      explanation: explanationOverride ??
          '${expl.title} — ${expl.detail}${dCode != null ? ' (Discord code: $dCode)' : ''}',
      retryAfterMs: retryAfterMs,
    );
  }

  /// Status ringkas untuk paparan luar.
  static String describeStatusCode(int? code) {
    if (code == null) return 'NETWORK';
    if (code >= 200 && code < 300) return 'SUCCESS';
    if (code == 429) return 'RATE LIMIT';
    return 'ERROR';
  }
}

/// Bungkusan jsonEncode yang selamat untuk badan kecil.
String jsonEncodeSafe(Object? o) {
  try {
    return const JsonEncoder().convert(o);
  } catch (_) {
    return '{}';
  }
}

