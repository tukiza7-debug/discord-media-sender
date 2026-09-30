/// Semua model data aplikasi dalam satu fail untuk rujukan mudah.
library;

import 'package:discord_media_sender/core/constants.dart';

/// Mod hantaran.
enum SendMode { webhook, bot }

extension SendModeX on SendMode {
  String get label => this == SendMode.webhook ? 'Webhook' : 'Bot';
}

/// Jenis media.
enum MediaType { image, video, other }

/// Status fail dalam senarai pilihan.
enum MediaStatus {
  ready, // sedia dihantar
  oversized, // melebihi had saiz
  limitExceeded, // melebihi had kuantiti
  missing, // fail tidak dijumpai
  sent,
  failed,
  cancelled,
}

extension MediaStatusX on MediaStatus {
  /// B05: 'ready' boleh dihantar; 'cancelled' (baki selepas batal) juga
  /// boleh dihantar semula melalui tindakan 'Send remaining'/'Send'.
  bool get canSend => this == MediaStatus.ready || this == MediaStatus.cancelled;

  String get label => switch (this) {
        MediaStatus.ready => 'Ready',
        MediaStatus.oversized => 'Too large',
        MediaStatus.limitExceeded => 'Limit',
        MediaStatus.missing => 'Missing',
        MediaStatus.sent => 'Sent',
        MediaStatus.failed => 'Failed',
        MediaStatus.cancelled => 'Cancelled',
      };
}

/// Satu fail media dalam baris giliran.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.type,
    required this.mimeType,
    this.status = MediaStatus.ready,
    this.note,
  });

  final String id; // hash laluan untuk pengecaman unik
  final String path;
  final String name;
  final int sizeBytes;
  final MediaType type;
  final String mimeType;
  final MediaStatus status;
  final String? note; // sebab jika dilangkau

  MediaItem copyWith({MediaStatus? status, String? note}) => MediaItem(
        id: id,
        path: path,
        name: name,
        sizeBytes: sizeBytes,
        type: type,
        mimeType: mimeType,
        status: status ?? this.status,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'sizeBytes': sizeBytes,
        'type': type.name,
        'mimeType': mimeType,
        'status': status.name,
        'note': note,
      };

  static MediaItem fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String,
        path: j['path'] as String,
        name: j['name'] as String,
        sizeBytes: j['sizeBytes'] as int,
        type: MediaType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => MediaType.other,
        ),
        mimeType: j['mimeType'] as String,
        status: MediaStatus.values.firstWhere(
          (e) => e.name == (j['status'] ?? 'ready'),
          orElse: () => MediaStatus.ready,
        ),
        note: j['note'] as String?,
      );
}

/// Konfigurasi hantaran (disimpan dalam flutter_secure_storage).
class SendConfig {
  const SendConfig({
    this.mode = SendMode.webhook,
    this.webhookUrl = '',
    this.botName = '',
    this.avatarUrl = '',
    this.botToken = '',
    this.channelId = '',
    this.channelName = '',
  });

  final SendMode mode;
  final String webhookUrl;
  final String botName; // pilihan (webhook sahaja)
  final String avatarUrl; // pilihan (webhook sahaja)
  final String botToken;
  final String channelId;
  final String channelName;

  bool get webhookReady => mode == SendMode.webhook && webhookUrl.trim().isNotEmpty;

  bool get botReady =>
      mode == SendMode.bot &&
      botToken.trim().isNotEmpty &&
      channelId.trim().isNotEmpty;

  bool get readyToSend => mode == SendMode.webhook ? webhookReady : botReady;

  /// Sasaran dalam bentuk ringkas untuk paparan (ditapis).
  String get targetLabel =>
      mode == SendMode.webhook ? '#webhook' : (channelName.isEmpty ? '#$channelId' : '#$channelName');

  SendConfig copyWith({
    SendMode? mode,
    String? webhookUrl,
    String? botName,
    String? avatarUrl,
    String? botToken,
    String? channelId,
    String? channelName,
  }) =>
      SendConfig(
        mode: mode ?? this.mode,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        botName: botName ?? this.botName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        botToken: botToken ?? this.botToken,
        channelId: channelId ?? this.channelId,
        channelName: channelName ?? this.channelName,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'webhookUrl': webhookUrl,
        'botName': botName,
        'avatarUrl': avatarUrl,
        'botToken': botToken,
        'channelId': channelId,
        'channelName': channelName,
      };

  static SendConfig fromJson(Map<String, dynamic> j) => SendConfig(
        mode: j['mode'] == 'bot' ? SendMode.bot : SendMode.webhook,
        webhookUrl: (j['webhookUrl'] ?? '') as String,
        botName: (j['botName'] ?? '') as String,
        avatarUrl: (j['avatarUrl'] ?? '') as String,
        botToken: (j['botToken'] ?? '') as String,
        channelId: (j['channelId'] ?? '') as String,
        channelName: (j['channelName'] ?? '') as String,
      );
}

/// Server & channel untuk mod bot.
class GuildInfo {
  const GuildInfo({required this.id, required this.name});
  final String id;
  final String name;
}

class ChannelInfo {
  const ChannelInfo({required this.id, required this.name, required this.guildId});
  final String id;
  final String name;
  final String guildId;
}

/// Keputusan uji sambungan.
class TestResult {
  const TestResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

/// Klasifikasi status log respons.
enum LogStatus { success, clientError, serverError, networkError, rateLimited, cancelled }

extension LogStatusX on LogStatus {
  bool get isError =>
      this == LogStatus.clientError || this == LogStatus.serverError || this == LogStatus.networkError;
}

/// Satu entri log respons Discord (data rahsia sudah ditapis).
class ResponseLogEntry {
  const ResponseLogEntry({
    required this.id,
    required this.batchNumber,
    required this.totalBatches,
    required this.fileCount,
    required this.fileNames,
    required this.filePaths,
    required this.endpoint,
    required this.method,
    required this.status,
    this.statusCode,
    this.reasonPhrase,
    required this.latencyMs,
    required this.uploadBytes,
    required this.speedMBps,
    required this.attempt,
    required this.timestamp,
    this.rateLimitHeaders = const {},
    this.responseJson,
    this.errorMessage,
    this.explanation,
    this.retryAfterMs,
  });

  final String id;
  final int batchNumber;
  final int totalBatches;
  final int fileCount;
  final List<String> fileNames;
  final List<String> filePaths;
  final String endpoint; // sentiasa ditapis
  final String method;
  final LogStatus status;
  final int? statusCode;
  final String? reasonPhrase;
  final int latencyMs;
  final int uploadBytes;
  final double speedMBps;
  final int attempt; // percubaan ke-N
  final DateTime timestamp;
  final Map<String, String> rateLimitHeaders;
  final Object? responseJson; // sudah disanitasi
  final String? errorMessage;
  final String? explanation; // penerangan BM
  final int? retryAfterMs; // untuk kad countdown 429
}

/// Keadaan enjin hantaran.
enum EngineState { idle, running, paused, cancelling, done, cancelled, failed }

/// Snapshot progres hantaran.
class UploadProgress {
  const UploadProgress({
    required this.state,
    required this.totalBatches,
    required this.currentBatch,
    required this.totalFiles,
    required this.successFiles,
    required this.failedFiles,
    required this.uploadedBytes,
    required this.totalBytes,
    required this.speedMBps,
    this.message,
  });

  final EngineState state;
  final int totalBatches;
  final int currentBatch; // batch yang sedang/selalu diproses
  final int totalFiles;
  final int successFiles;
  final int failedFiles;
  final int uploadedBytes;
  final int totalBytes;
  final double speedMBps;
  final String? message;

  double get fraction =>
      totalBytes > 0 ? (uploadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  UploadProgress copyWith({
    EngineState? state,
    int? currentBatch,
    int? successFiles,
    int? failedFiles,
    int? uploadedBytes,
    double? speedMBps,
    String? message,
  }) =>
      UploadProgress(
        state: state ?? this.state,
        totalBatches: totalBatches,
        currentBatch: currentBatch ?? this.currentBatch,
        totalFiles: totalFiles,
        successFiles: successFiles ?? this.successFiles,
        failedFiles: failedFiles ?? this.failedFiles,
        uploadedBytes: uploadedBytes ?? this.uploadedBytes,
        totalBytes: totalBytes,
        speedMBps: speedMBps ?? this.speedMBps,
        message: message ?? this.message,
      );
}

/// Rekod sesi sejarah.
class SessionRecord {
  const SessionRecord({
    this.id,
    required this.startedAt,
    required this.endedAt,
    required this.mode,
    required this.target,
    required this.totalFiles,
    required this.successCount,
    required this.failedCount,
    required this.status,
    this.reason,
  });

  final int? id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String mode; // 'webhook' | 'bot'
  final String target; // sudah ditapis
  final int totalFiles;
  final int successCount;
  final int failedCount;
  final String status; // 'completed' | 'partial' | 'failed' | 'cancelled'

  /// 4a: sebab status bukan-completed (null untuk sesi completed & sesi
  /// lama yang dicipta sebelum kemas kini ini).
  final String? reason;

  Map<String, dynamic> toMap() => {
        'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt.millisecondsSinceEpoch,
        'mode': mode,
        'target': target,
        'total_files': totalFiles,
        'success': successCount,
        'failed': failedCount,
        'status': status,
        'reason': reason,
      };

  static SessionRecord fromMap(Map<String, dynamic> m) => SessionRecord(
        id: m['id'] as int?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        mode: (m['mode'] ?? 'webhook') as String,
        target: (m['target'] ?? '') as String,
        totalFiles: (m['total_files'] ?? 0) as int,
        successCount: (m['success'] ?? 0) as int,
        failedCount: (m['failed'] ?? 0) as int,
        // Normalise legacy Malay status keys written by older versions.
        status: _normalizeStatus((m['status'] ?? 'completed') as String),
        reason: m['reason'] as String?,
      );

  static String _normalizeStatus(String s) {
    const legacy = {
      'selesai': 'completed',
      'separa': 'partial',
      'gagal': 'failed',
      'dibatalkan': 'cancelled',
      'berjalan': 'running',
    };
    return legacy[s] ?? s;
  }
}

/// Rekod kegagalan (batch/fail yang gagal selepas cubaan habis).
class FailedRecord {
  const FailedRecord({
    this.id,
    this.sessionId,
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.batchIndex,
    required this.httpCode,
    this.discordCode,
    required this.errorMessage,
    required this.mode,
    required this.target,
    required this.createdAt,
  });

  final int? id;
  final int? sessionId;
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final int batchIndex;
  final int? httpCode; // null = ralat rangkaian
  final int? discordCode; // B24: kod ralat Discord (cth. 40005)
  final String errorMessage;
  final String mode;
  final String target;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'file_name': fileName,
        'file_path': filePath,
        'size_bytes': sizeBytes,
        'batch_index': batchIndex,
        'http_code': httpCode,
        'discord_code': discordCode,
        'error_message': errorMessage,
        'mode': mode,
        'target': target,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static FailedRecord fromMap(Map<String, dynamic> m) => FailedRecord(
        id: m['id'] as int?,
        sessionId: m['session_id'] as int?,
        fileName: (m['file_name'] ?? '') as String,
        filePath: (m['file_path'] ?? '') as String,
        sizeBytes: (m['size_bytes'] ?? 0) as int,
        batchIndex: (m['batch_index'] ?? 0) as int,
        httpCode: m['http_code'] as int?,
        discordCode: m['discord_code'] as int?,
        errorMessage: (m['error_message'] ?? '') as String,
        mode: (m['mode'] ?? 'webhook') as String,
        target: (m['target'] ?? '') as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] ?? 0) as int),
      );

  /// Bina semula MediaItem untuk 'Cuba Semula'.
  MediaItem toMediaItem() {
    final name = fileName;
    final type = MediaCatalog.isVideo(name)
        ? MediaType.video
        : (MediaCatalog.isImage(name) ? MediaType.image : MediaType.other);
    return MediaItem(
      id: 'retry-${filePath.hashCode}-${createdAt.millisecondsSinceEpoch}',
      path: filePath,
      name: name,
      sizeBytes: sizeBytes,
      type: type,
      mimeType: MediaCatalog.mimeType(name),
    );
  }
}
