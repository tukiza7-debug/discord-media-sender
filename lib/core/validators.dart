/// Validates configuration input with clear English error messages.
library;

import '../models/models.dart';

/// Validates configuration input with clear English error messages.
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
    if (value.isEmpty) return 'Webhook URL is required';
    if (!value.startsWith('https://')) {
      return 'The URL must start with https://';
    }
    if (!_webhookRe.hasMatch(value)) {
      return 'Invalid webhook URL format';
    }
    return null;
  }

  static String? botToken(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Bot token is required';
    if (!_tokenRe.hasMatch(value)) {
      return 'Invalid bot token format';
    }
    return null;
  }

  static String? channelId(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Channel ID is required';
    if (!_channelIdRe.hasMatch(value)) {
      return 'The Channel ID must be numeric (snowflake)';
    }
    return null;
  }

  static String? avatarUrl(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return null; // optional
    final ok = Uri.tryParse(value);
    if (ok == null || !ok.isAbsolute || !value.startsWith('http')) {
      return 'Invalid avatar URL';
    }
    return null;
  }

  static bool isWebhookUrlValid(String v) => _webhookRe.hasMatch(v.trim());
}

/// B11: konfigurasi dianggap SAH hanya bila medan aktif lulus validator
/// (bukan sekadar tidak kosong). Digunakan untuk melumpuhkan Send/Test
/// dan memaparkan errorText sebaris.
bool configValid(SendConfig config) {
  if (config.mode == SendMode.webhook) {
    return Validators.isWebhookUrlValid(config.webhookUrl) &&
        Validators.avatarUrl(config.avatarUrl) == null;
  }
  return Validators.botToken(config.botToken) == null &&
      Validators.channelId(config.channelId) == null;
}

