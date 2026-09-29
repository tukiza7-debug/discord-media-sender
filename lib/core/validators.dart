/// Validasi input konfigurasi dengan mesej ralat Bahasa Melayu.
class Validators {
  Validators._();

  static final _webhookRe = RegExp(
    r'^https://(discord\.com|discordapp\.com|ptb\.discord\.com|canary\.discord\.com)/api/webhooks/\d+/[A-Za-z0-9_-]+$',
  );

  static final _tokenRe = RegExp(
    r'^[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{20,}$',
  );

  static final _channelIdRe = RegExp(r'^\d{5,25}$');

  static String? webhookUrl(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'URL webhook diperlukan';
    if (!value.startsWith('https://')) {
      return 'URL mesti bermula dengan https://';
    }
    if (!_webhookRe.hasMatch(value)) {
      return 'Format URL webhook tidak sah';
    }
    return null;
  }

  static String? botToken(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Token bot diperlukan';
    if (!_tokenRe.hasMatch(value)) {
      return 'Format token bot tidak sah';
    }
    return null;
  }

  static String? channelId(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Channel ID diperlukan';
    if (!_channelIdRe.hasMatch(value)) {
      return 'Channel ID mesti nombor (snowflake)';
    }
    return null;
  }

  static String? avatarUrl(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return null; // pilihan
    final ok = Uri.tryParse(value);
    if (ok == null || !ok.isAbsolute || !value.startsWith('http')) {
      return 'URL avatar tidak sah';
    }
    return null;
  }

  static bool isWebhookUrlValid(String v) => _webhookRe.hasMatch(v.trim());
}
