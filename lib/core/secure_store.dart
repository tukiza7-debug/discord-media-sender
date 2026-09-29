import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pembungkus storan selamat — SEMUA kelayakan (token, URL webhook)
/// disimpan di sini, bukan dalam repo atau plain text.
class SecureStore {
  SecureStore._();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(), // penyulitan kuat lalai (AES-GCM + RSA OAEP)
  );

  // Kunci
  static const _kMode = 'cfg_mode';
  static const _kWebhookUrl = 'cfg_webhook_url';
  static const _kBotName = 'cfg_bot_name';
  static const _kAvatarUrl = 'cfg_avatar_url';
  static const _kBotToken = 'cfg_bot_token';
  static const _kChannelId = 'cfg_channel_id';
  static const _kChannelName = 'cfg_channel_name';
  static const _kThemeMode = 'set_theme_mode';
  static const _kOrientation = 'set_orientation';
  static const _kOnboardingDone = 'set_onboarding_done';

  static Future<Map<String, String>> loadConfig() async {
    final all = await _storage.readAll();
    return {
      'mode': all[_kMode] ?? 'webhook',
      'webhookUrl': all[_kWebhookUrl] ?? '',
      'botName': all[_kBotName] ?? '',
      'avatarUrl': all[_kAvatarUrl] ?? '',
      'botToken': all[_kBotToken] ?? '',
      'channelId': all[_kChannelId] ?? '',
      'channelName': all[_kChannelName] ?? '',
    };
  }

  static Future<void> saveConfigField(String key, String value) async {
    final map = <String, String>{
      'mode': _kMode,
      'webhookUrl': _kWebhookUrl,
      'botName': _kBotName,
      'avatarUrl': _kAvatarUrl,
      'botToken': _kBotToken,
      'channelId': _kChannelId,
      'channelName': _kChannelName,
    };
    final k = map[key];
    if (k == null) return;
    if (value.isEmpty) {
      await _storage.delete(key: k);
    } else {
      await _storage.write(key: k, value: value);
    }
  }

  static Future<({String themeMode, String orientation, bool onboardingDone})>
      loadSettings() async {
    final all = await _storage.readAll();
    return (
      themeMode: all[_kThemeMode] ?? 'dark',
      orientation: all[_kOrientation] ?? 'auto',
      onboardingDone: (all[_kOnboardingDone] ?? 'false') == 'true',
    );
  }

  static Future<void> saveThemeMode(String v) =>
      _storage.write(key: _kThemeMode, value: v);

  static Future<void> saveOrientation(String v) =>
      _storage.write(key: _kOrientation, value: v);

  static Future<void> setOnboardingDone() =>
      _storage.write(key: _kOnboardingDone, value: 'true');

  static Future<void> wipeAll() => _storage.deleteAll();
}
