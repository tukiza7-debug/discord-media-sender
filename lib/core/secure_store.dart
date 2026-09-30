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
  // 1b: pilihan kemas kini automatik + throttle + versi dilangkau.
  static const _kAutoUpdate = 'set_auto_update';
  static const _kUpdateLastCheckMs = 'set_update_last_check_ms';
  static const _kUpdateSkippedTag = 'set_update_skipped_tag';
  // 2d: tetapan sambung semula (bukan rahsia) untuk task isolate.
  static const _kResumeSessionId = 'res_session_id';
  static const _kResumeMaxMB = 'res_max_mb';
  static const _kResumeCaption = 'res_caption';
  // 2f: prompt penjelasan bateri sekali sahaja.
  static const _kBatteryAsked = 'set_battery_asked';

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

  // ------------------------------------------------------- kemas kini

  static Future<bool> loadAutoUpdate() async {
    try {
      final all = await _storage.readAll();
      return (all[_kAutoUpdate] ?? 'true') == 'true'; // lalai ON (1b)
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveAutoUpdate(bool v) async {
    try {
      await _storage.write(key: _kAutoUpdate, value: v ? 'true' : 'false');
    } catch (_) {}
  }

  /// Throttle semakan automatik — sekurang-kurangnya 6 jam di antara (1b).
  static Future<int> loadLastUpdateCheckMs() async {
    try {
      final all = await _storage.readAll();
      return int.tryParse(all[_kUpdateLastCheckMs] ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> saveLastUpdateCheckMs(int ms) async {
    try {
      await _storage.write(key: _kUpdateLastCheckMs, value: ms.toString());
    } catch (_) {}
  }

  /// Versi yang dilangkau pengguna (1c) — semakan automatik tidak
  /// mengganggu lagi untuk versi itu.
  static Future<String> loadSkippedUpdateTag() async {
    try {
      final all = await _storage.readAll();
      return all[_kUpdateSkippedTag] ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveSkippedUpdateTag(String tag) async {
    try {
      if (tag.isEmpty) {
        await _storage.delete(key: _kUpdateSkippedTag);
      } else {
        await _storage.write(key: _kUpdateSkippedTag, value: tag);
      }
    } catch (_) {}
  }

  // ---------------------------------------------- sambung semula (2d)

  /// Tetapan sesi yang sedang berjalan — ditulis oleh task isolate semasa
  /// start; dibaca semula oleh onStart selepas proses mati. TIADA RAHSIA.
  static Future<void> saveResumeSettings({
    required int sessionId,
    required int maxFileMB,
    required String caption,
  }) async {
    try {
      await _storage.write(key: _kResumeSessionId, value: sessionId.toString());
      await _storage.write(key: _kResumeMaxMB, value: maxFileMB.toString());
      await _storage.write(key: _kResumeCaption, value: caption);
    } catch (_) {}
  }

  static Future<({int? sessionId, int maxFileMB, String caption})>
      loadResumeSettings() async {
    try {
      final all = await _storage.readAll();
      return (
        sessionId: int.tryParse(all[_kResumeSessionId] ?? ''),
        maxFileMB: int.tryParse(all[_kResumeMaxMB] ?? '') ?? 20,
        caption: all[_kResumeCaption] ?? '',
      );
    } catch (_) {
      return (sessionId: null, maxFileMB: 20, caption: '');
    }
  }

  static Future<void> clearResumeSettings() async {
    try {
      await _storage.delete(key: _kResumeSessionId);
      await _storage.delete(key: _kResumeMaxMB);
      await _storage.delete(key: _kResumeCaption);
    } catch (_) {}
  }

  // ------------------------------------------------------- bateri (2f)

  static Future<bool> loadBatteryAsked() async {
    try {
      final all = await _storage.readAll();
      return (all[_kBatteryAsked] ?? 'false') == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveBatteryAsked() async {
    try {
      await _storage.write(key: _kBatteryAsked, value: 'true');
    } catch (_) {}
  }

  static Future<void> wipeAll() => _storage.deleteAll();

  /// B06/B25: wipe yang tidak pernah melempar.
  static Future<void> safeWipeAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}
