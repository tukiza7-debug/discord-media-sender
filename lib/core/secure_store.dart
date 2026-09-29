import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pembungkus storan selamat — SEMUA kelayakan (token, URL webhook)
/// disimpan di sini, bukan dalam repo atau plain text.
///
/// B06: jika storan selamat melempar (auto-backup restore, reinstall,
/// keystone reset), app TIDAK digantung — data rosak dibuang dan lalai
/// digunakan (lihat loadConfigSafe / loadSettingsSafe).
class SecureStore {
  SecureStore._();
  static const _storage = FlutterSecureStorage(
    // resetOnError: true (disemak — tersedia dalam flutter_secure_storage
    // 11.2.0) — data yang gagal dinyahsulit dibuang secara automatik oleh
    // plugin, jangan biarkan pembacaan terus melempar.
    aOptions: AndroidOptions(resetOnError: true),
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
  static const _kMaxFileMB = 'set_max_file_mb';

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

  /// B06: muat konfigurasi dengan selamat — jika storan selamat melempar,
  /// buang data rosak (deleteAll) dan teruskan dengan nilai LALAI.
  static Future<Map<String, String>> loadConfigSafe() async {
    try {
      return await loadConfig();
    } catch (_) {
      await safeWipeAll();
      return const {
        'mode': 'webhook',
        'webhookUrl': '',
        'botName': '',
        'avatarUrl': '',
        'botToken': '',
        'channelId': '',
        'channelName': '',
      };
    }
  }

  /// B11: ujian boleh ganti penulis (seam) — @visibleForTesting.
  @visibleForTesting
  static Future<void> Function(String key, String value)? saveOverride;

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
    final saver = saveOverride;
    if (saver != null) {
      await saver(key, value);
      return;
    }
    if (value.isEmpty) {
      await _storage.delete(key: k);
    } else {
      await _storage.write(key: k, value: value);
    }
  }

  static Future<({String themeMode, String orientation, bool onboardingDone, int maxFileMB})>
      loadSettings() async {
    final all = await _storage.readAll();
    return (
      themeMode: all[_kThemeMode] ?? 'dark',
      orientation: all[_kOrientation] ?? 'auto',
      onboardingDone: (all[_kOnboardingDone] ?? 'false') == 'true',
      maxFileMB: int.tryParse(all[_kMaxFileMB] ?? '') ?? 20,
    );
  }

  /// B06: muat tetapan dengan selamat (lihat loadConfigSafe).
  static Future<({String themeMode, String orientation, bool onboardingDone, int maxFileMB})>
      loadSettingsSafe() async {
    try {
      return await loadSettings();
    } catch (_) {
      await safeWipeAll();
      return (themeMode: 'dark', orientation: 'auto', onboardingDone: false, maxFileMB: 20);
    }
  }

  static Future<void> saveThemeMode(String v) =>
      _storage.write(key: _kThemeMode, value: v);

  static Future<void> saveOrientation(String v) =>
      _storage.write(key: _kOrientation, value: v);

  static Future<void> saveMaxFileMB(int mb) =>
      _storage.write(key: _kMaxFileMB, value: mb.toString());

  static Future<void> setOnboardingDone() =>
      _storage.write(key: _kOnboardingDone, value: 'true');

  static Future<void> wipeAll() => _storage.deleteAll();

  /// B06/B25: wipe yang tidak pernah melempar.
  static Future<void> safeWipeAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}
