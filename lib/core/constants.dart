/// Had & pemalar aplikasi + katalog media yang disokong.
class AppLimits {
  AppLimits._();

  static const int batchSize = 10; // had Discord: 10 lampiran per mesej
  static const int captionMaxLength = 2000;
  static const int maxRetries = 3;
  static const int maxRateLimitWaits = 6;
  static const int responseLogCapacity = 500;

  /// PRESET had saiz muat naik per fail (MB) — mengikut tier server Discord:
  /// 10 MB (lama), 20 MB (server tanpa boost, sejak 13 Ogo 2026),
  /// 50 MB (Boost Level 2), 100 MB (Boost Level 3).
  /// Pengguna pilih had aktif dalam Tetapan (lalai 20 MB).
  static const List<int> fileSizePresetsMB = [10, 20, 50, 100];
  static const int defaultMaxFileMB = 20;

  /// Had saiz ZIP INPUT (berasingan daripada had muat naik).
  static const int maxZipBytes = 5 * 1024 * 1024 * 1024; // 5 GB

  /// Had jumlah TIDARAMPAT selepas ekstrak ZIP (pertahanan zip-bomb).
  static const int maxZipExtractBytes = 5 * 1024 * 1024 * 1024; // 5 GB

  /// Backoff eksponensial antara percubaan semula (saat).
  static const List<int> retryBackoffSeconds = [1, 2, 4];

  /// Pengawal masa: satu percubaan batch tidak boleh melebihi ini.
  /// Mencegah sesi tergantung selamanya apabila sambungan tersadai.
  static const Duration batchAttemptTimeout = Duration(minutes: 15);

  /// Anggaran throughput muat naik minimum (200 KB/s) untuk penskalaan
  /// masa-luar percubaan: batch besar diberi masa yang lebih panjang.
  static const int attemptTimeoutMinKBps = 200;

  /// Muat naik dianggap tersadai jika tiada bait terhantar selama ini.
  static const Duration uploadStallTimeout = Duration(seconds: 90);

  /// Jeda minimum antara dua kemas kini progres UI (kurangkan beban rebuild).
  static const Duration progressThrottle = Duration(milliseconds: 120);

  /// Tunggu minimum/maksimum semasa menghormati 429 (Retry-After).
  static const int minRateLimitWaitMs = 250;
  static const int maxRateLimitWaitMs = 10 * 60 * 1000; // 10 minit

  /// Mentions dimatikan secara lalai dalam kapsyen (elak mass-mention);
  /// tukar kepada true untuk membenarkan @everyone/@role/@user.
  static const bool allowCaptionMentions = false;
}

/// Asas API Discord (versi v10).
class DiscordConstants {
  DiscordConstants._();
  static const apiBase = 'https://discord.com/api/v10';
}

/// Ekstensi media yang disokong + pemetaan MIME.
class MediaCatalog {
  MediaCatalog._();

  static const imageExtensions = [
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'avif',
    'heic', 'heif', 'tif', 'tiff', 'jfif', 'jpe', 'apng', 'svg', 'ico',
  ];

  static const videoExtensions = [
    'mp4', 'webm', 'mov', 'mkv', 'avi', 'mpeg', 'mpg', 'ogg', 'ogv', '3gp',
  ];

  /// Senarai ekstensi untuk pilihan fail (tanpa titik).
  static List<String> get allowedExtensions => [...imageExtensions, ...videoExtensions];

  static bool isSupported(String fileName) {
    final ext = _extOf(fileName);
    return imageExtensions.contains(ext) || videoExtensions.contains(ext);
  }

  static bool isImage(String fileName) => imageExtensions.contains(_extOf(fileName));
  static bool isVideo(String fileName) => videoExtensions.contains(_extOf(fileName));

  static String mimeType(String fileName) {
    final ext = _extOf(fileName);
    const map = <String, String>{
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'avif': 'image/avif',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'tif': 'image/tiff',
      'tiff': 'image/tiff',
      'jfif': 'image/jpeg',
      'jpe': 'image/jpeg',
      'apng': 'image/apng',
      'svg': 'image/svg+xml',
      'ico': 'image/x-icon',
      'mp4': 'video/mp4',
      'webm': 'video/webm',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'avi': 'video/x-msvideo',
      'mpeg': 'video/mpeg',
      'mpg': 'video/mpeg',
      'ogg': 'video/ogg',
      'ogv': 'video/ogg',
      '3gp': 'video/3gpp',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  static String _extOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
