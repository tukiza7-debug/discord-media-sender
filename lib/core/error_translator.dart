import 'package:dio/dio.dart';

/// Terjemahan ralat teknikal kepada Bahasa Melayu yang mudah difahami,
/// beserta cadangan penyelesaian.
class ErrorExplanation {
  const ErrorExplanation({
    required this.title,
    required this.detail,
    this.suggestions = const [],
  });

  final String title;
  final String detail;
  final List<String> suggestions;

  @override
  String toString() => title;
}

class ErrorTranslator {
  ErrorTranslator._();

  static const _httpTitles = <int, String>{
    400: 'Permintaan tidak sah',
    401: 'Token tidak sah',
    403: 'Akses dihalang',
    404: 'Tidak dijumpai',
    405: 'Kaedah tidak dibenarkan',
    413: 'Muatan terlalu besar',
    429: 'Had kadar (rate limit)',
  };

  static const _discordCodes = <int, String>{
    0: 'Ralat umum',
    10003: 'Channel tidak dijumpai',
    10004: 'Server tidak dijumpai',
    10057: 'Channel webhook tidak sah',
    30007: 'Had webhook server capai maksimum',
    40005: 'Fail melebihi saiz maksimum',
    50001: 'Tiada akses ke channel',
    50006: 'Mesej tidak boleh kosong',
    50013: 'Kebenaran tidak mencukupi',
    50046: 'Kebenaran webhook tidak sah',
    50074: 'Channel tidak menyokong hantaran fail',
  };

  /// Tafsir ralat daripada status HTTP + kod ralat Discord + jenis ralat.
  static ErrorExplanation explain({
    int? statusCode,
    int? discordCode,
    Object? error,
  }) {
    // Ralat rangkaian / Dio
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.cancel:
          return const ErrorExplanation(
            title: 'Permintaan dibatalkan',
            detail: 'Hantaran dihentikan sebelum selesai.',
          );
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const ErrorExplanation(
            title: 'Tamat masa sambungan',
            detail: 'Sambungan ke Discord terlalu lama untuk bertindak balas.',
            suggestions: ['Semak sambungan internet anda', 'Cuba semula nanti'],
          );
        case DioExceptionType.connectionError:
          return const ErrorExplanation(
            title: 'Tiada sambungan internet',
            detail: 'Peranti gagal berhubung dengan Discord.',
            suggestions: [
              'Semak Wi-Fi atau data mudah alih',
              'Pastikan tiada VPN/firewall menyekat discord.com',
            ],
          );
        case DioExceptionType.badCertificate:
          return const ErrorExplanation(
            title: 'Sijil tidak selamat',
            detail: 'Sambungan HTTPS ke Discord tidak dapat disahkan.',
            suggestions: ['Semak tarikh & masa peranti'],
          );
        default:
          break;
      }
    }

    // Kod khusus Discord
    if (discordCode != null && _discordCodes.containsKey(discordCode)) {
      return _forDiscordCode(discordCode);
    }

    // Status HTTP
    if (statusCode != null) {
      if (statusCode == 429) {
        return const ErrorExplanation(
          title: 'Had kadar Discord',
          detail: 'Terlalu banyak permintaan dalam masa singkat. '
              'Aplikasi akan menunggu mengikut arahan Discord sebelum cuba semula.',
          suggestions: ['Kurangkan bilangan fail atau cuba nanti'],
        );
      }
      if (statusCode >= 500) {
        return ErrorExplanation(
          title: 'Masalah pelayan Discord ($statusCode)',
          detail: 'Pelayan Discord mengalami gangguan sementara.',
          suggestions: ['Cuba semula dalam beberapa minit', 'Semak status Discord'],
        );
      }
      final t = _httpTitles[statusCode];
      if (t != null) return _forHttpTitle(statusCode, t);
      return ErrorExplanation(
        title: 'Ralat HTTP $statusCode',
        detail: 'Discord menolak permintaan ini.',
        suggestions: ['Semak konfigurasi dan fail, kemudian cuba semula'],
      );
    }

    return const ErrorExplanation(
      title: 'Ralat tidak diketahui',
      detail: 'Sesuatu yang tidak dijangka berlaku semasa menghantar.',
      suggestions: ['Cuba semula; jika berterusan, semak log respons'],
    );
  }

  static ErrorExplanation _forDiscordCode(int code) {
    switch (code) {
      case 10003:
        return const ErrorExplanation(
          title: 'Channel tidak dijumpai',
          detail: 'Channel ID yang diberi tidak wujud atau bot tiada di sana.',
          suggestions: ['Semak Channel ID', 'Pastikan bot ditambah ke server tersebut'],
        );
      case 10004:
        return const ErrorExplanation(
          title: 'Server tidak dijumpai',
          detail: 'Server (guild) tidak wujud atau tidak boleh diakses.',
        );
      case 30007:
        return const ErrorExplanation(
          title: 'Had webhook penuh',
          detail: 'Server ini telah mencapai had maksimum webhook.',
        );
      case 40005:
        return const ErrorExplanation(
          title: 'Fail terlalu besar',
          detail: 'Saiz fail melebihi had yang dibenarkan Discord untuk server ini.',
          suggestions: ['Mampatkan video/gambar', 'Gunakan fail yang lebih kecil'],
        );
      case 50001:
        return const ErrorExplanation(
          title: 'Tiada kebenaran akses',
          detail: 'Bot tidak mempunyai kebenaran untuk melihat/menghantar di channel ini.',
          suggestions: [
            'Pastikan bot mempunyai kebenaran Send Messages & Attach Files',
            'Semak kebenaran khusus channel',
          ],
        );
      case 50006:
        return const ErrorExplanation(
          title: 'Mesej kosong',
          detail: 'Tiada teks atau fail dihantar dalam permintaan ini.',
        );
      case 50013:
        return const ErrorExplanation(
          title: 'Kebenaran tidak mencukupi',
          detail: 'Peranan bot tidak mempunyai kebenaran yang diperlukan.',
          suggestions: [
            'Naikkan kedudukan peranan bot',
            'Benarkan Send Messages, Attach Files dan Embed Links',
          ],
        );
      case 50046:
        return const ErrorExplanation(
          title: 'Kebenaran webhook tidak sah',
          detail: 'Webhook tidak mempunyai kebenaran yang diperlukan.',
        );
      case 50074:
        return const ErrorExplanation(
          title: 'Channel tidak menyokong fail',
          detail: 'Channel ini tidak membenarkan hantaran lampiran.',
        );
      default:
        return ErrorExplanation(
          title: 'Ralat Discord (kod $code)',
          detail: 'Discord memulangkan kod ralat khusus ini.',
        );
    }
  }

  static ErrorExplanation _forHttpTitle(int status, String title) {
    switch (status) {
      case 400:
        return const ErrorExplanation(
          title: 'Permintaan tidak sah',
          detail: 'Format permintaan tidak diterima Discord.',
          suggestions: [
            'Pastikan URL webhook betul',
            'Pastikan jenis fail disokong',
          ],
        );
      case 401:
        return const ErrorExplanation(
          title: 'Token tidak sah',
          detail: 'Token bot atau kelayakan webhook tidak diterima. '
              'Token mungkin salah, direset, atau dipadam.',
          suggestions: [
            'Semak semula token bot di Developer Portal',
            'Jika token baru direset, kemas kini dalam Tetapan',
            'Pastikan tiada ruang kosong di awal/akhir token',
          ],
        );
      case 403:
        return const ErrorExplanation(
          title: 'Akses dihalang',
          detail: 'Token sah tetapi tiada kebenaran untuk tindakan ini.',
          suggestions: [
            'Semak kebenaran bot di channel sasaran',
            'Pastikan webhook masih wujud dan tidak dipadam',
          ],
        );
      case 404:
        return const ErrorExplanation(
          title: 'Tidak dijumpai',
          detail: 'Webhook atau channel tidak wujud lagi (mungkin telah dipadam).',
          suggestions: ['Semak URL webhook / Channel ID'],
        );
      case 413:
        return const ErrorExplanation(
          title: 'Muatan terlalu besar',
          detail: 'Jumlah saiz permintaan melebihi had Discord.',
          suggestions: ['Kurangkan saiz atau bilangan fail bagi setiap batch'],
        );
      default:
        return ErrorExplanation(title: title, detail: 'Ralat HTTP $status dari Discord.');
    }
  }

  /// Ringkasan satu ayat untuk snackbar/senarai.
  static String shortReason({int? statusCode, int? discordCode, Object? error}) =>
      explain(statusCode: statusCode, discordCode: discordCode, error: error).title;
}
