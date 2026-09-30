import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/secure_store.dart';
import '../models/models.dart';

/// Tema aplikasi.
enum AppThemeMode { dark, light, system }

extension AppThemeModeX on AppThemeMode {
  String get label {
    switch (this) {
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.system:
        return 'System';
    }
  }

  ThemeMode get themeMode {
    switch (this) {
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
}

/// Tetapan orientasi.
enum OrientationSetting { auto, portrait, landscape }

extension OrientationSettingX on OrientationSetting {
  String get label {
    switch (this) {
      case OrientationSetting.auto:
        return 'Auto';
      case OrientationSetting.portrait:
        return 'Portrait';
      case OrientationSetting.landscape:
        return 'Landscape';
    }
  }
}

/// Konfigurasi hantaran (disimpan dalam stor selamat).
///
/// B11 — pembetulan:
/// - SETIAP medan ditulis satu demi satu (bukan tulis semula 7 medan);
/// - tulisan DIBUANG SEKAT (debounce 400 ms) + diserikan melalui satu
///   giliran async — ketikan pantas tidak lagi menimpa dgn nilai lama;
/// - flush semasa dispose.
class ConfigNotifier extends StateNotifier<SendConfig> {
  ConfigNotifier() : super(const SendConfig());

  Timer? _debounce;
  final _pending = <String>{};
  Future<void> _queue = Future.value();

  Future<void> load() async {
    final map = await SecureStore.loadConfigSafe();
    state = SendConfig.fromJson(map);
  }

  void _scheduleSave(Set<String> keys) {
    _pending.addAll(keys);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _flush);
  }

  Future<void> _flush() async {
    if (!mounted) return;
    final keys = _pending.toList();
    _pending.clear();
    final json = state.toJson();
    // Giliran async tunggu: tulisan diserikan (tiada susunan terbalik).
    _queue = _queue.then((_) async {
      for (final key in keys) {
        try {
          await SecureStore.saveConfigField(key, json[key]?.toString() ?? '');
        } catch (_) {}
      }
    });
    await _queue;
  }

  /// Paksa simpan segera (dipanggil semasa dispose).
  Future<void> flush() async {
    _debounce?.cancel();
    if (_pending.isNotEmpty) {
      await _flush();
    } else {
      await _queue;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_pending.isNotEmpty) {
      // Fire-and-forget: state masih boleh dibaca sebelum shutdown.
      unawaited(_flush());
    }
    super.dispose();
  }

  void _set(SendConfig next, {String? onlyKey, Set<String> keys = const {}}) {
    state = next;
    if (onlyKey != null) {
      _scheduleSave({onlyKey});
    } else if (keys.isNotEmpty) {
      _scheduleSave(keys);
    } else {
      _scheduleSave(next.toJson().keys.toSet());
    }
  }

  void setMode(SendMode mode) => _set(state.copyWith(mode: mode));

  void setWebhookUrl(String v) =>
      _set(state.copyWith(webhookUrl: v.trim()), onlyKey: 'webhookUrl');

  void setBotName(String v) => _set(state.copyWith(botName: v), onlyKey: 'botName');

  void setAvatarUrl(String v) =>
      _set(state.copyWith(avatarUrl: v.trim()), onlyKey: 'avatarUrl');

  void setBotToken(String v) =>
      _set(state.copyWith(botToken: v.trim()), onlyKey: 'botToken');

  /// B11: suntingan ID channel MANUAL (name == null) MEMBERSHKAN
  /// channelName lama — dulu label & sejarah menunjukkan channel salah.
  void setChannel({required String id, String? name}) => _set(
        state.copyWith(channelId: id.trim(), channelName: name ?? ''),
        keys: {'channelId', 'channelName'},
      );

  void setChannelName(String v) =>
      _set(state.copyWith(channelName: v), onlyKey: 'channelName');
}

final configProvider =
    StateNotifierProvider<ConfigNotifier, SendConfig>((ref) => ConfigNotifier());

/// Tetapan aplikasi (tema, orientasi, onboarding, had saiz).
class SettingsState {
  const SettingsState({
    this.themeMode = AppThemeMode.dark,
    this.orientation = OrientationSetting.auto,
    this.onboardingDone = false,
    this.appVersion = '',
    this.maxFileMB = 20,
    this.autoUpdateEnabled = true,
  });

  final AppThemeMode themeMode;
  final OrientationSetting orientation;
  final bool onboardingDone;
  final String appVersion;

  /// B02: had saiz muat naik aktif (MB) — preset 10/20/50/100.
  final int maxFileMB;

  /// 1b: semakan kemas kini automatik (lalai ON).
  final bool autoUpdateEnabled;

  SettingsState copyWith({
    AppThemeMode? themeMode,
    OrientationSetting? orientation,
    bool? onboardingDone,
    String? appVersion,
    int? maxFileMB,
    bool? autoUpdateEnabled,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        orientation: orientation ?? this.orientation,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        appVersion: appVersion ?? this.appVersion,
        maxFileMB: maxFileMB ?? this.maxFileMB,
        autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      );
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  Future<void> load() async {
    final s = await SecureStore.loadSettingsSafe();
    final autoUpdate = await SecureStore.loadAutoUpdate();
    state = state.copyWith(
      themeMode: switch (s.themeMode) {
        'light' => AppThemeMode.light,
        'system' => AppThemeMode.system,
        _ => AppThemeMode.dark,
      },
      orientation: switch (s.orientation) {
        'portrait' => OrientationSetting.portrait,
        'landscape' => OrientationSetting.landscape,
        _ => OrientationSetting.auto,
      },
      onboardingDone: s.onboardingDone,
      maxFileMB: s.maxFileMB,
      autoUpdateEnabled: autoUpdate,
    );
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final names = {
      AppThemeMode.dark: 'dark',
      AppThemeMode.light: 'light',
      AppThemeMode.system: 'system',
    };
    await SecureStore.saveThemeMode(names[mode]!);
  }

  Future<void> setOrientation(OrientationSetting o) async {
    state = state.copyWith(orientation: o);
    final names = {
      OrientationSetting.auto: 'auto',
      OrientationSetting.portrait: 'portrait',
      OrientationSetting.landscape: 'landscape',
    };
    await SecureStore.saveOrientation(names[o]!);
  }

  /// B02: tukar had saiz muat naik (preset 10/20/50/100 MB).
  Future<void> setMaxFileMB(int mb) async {
    state = state.copyWith(maxFileMB: mb);
    await SecureStore.saveMaxFileMB(mb);
  }

  /// 1b: kemas kini automatik ON/OFF.
  Future<void> setAutoUpdateEnabled(bool v) async {
    state = state.copyWith(autoUpdateEnabled: v);
    await SecureStore.saveAutoUpdate(v);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingDone: true);
    await SecureStore.setOnboardingDone();
  }

  // B14: resetOnboarding() DIBUANG — "Show getting-started guide" kini
  // hanya membuka panduan sebagai laman (lihat settings_screen); nilai
  // persisted/in-memory onboardingDone TIDAK diubah lagi (dulu: reset
  // in-memory sahaja + MaterialApp.home bertukar di bawah route).
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) => SettingsNotifier());

/// Indeks tab navigasi utama (dikawal dari mana-mana skrin).
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// Helper JSON kecil (dipakai pembetulan masa depan).
Map<String, dynamic> decodeJsonMap(String raw) {
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> ? v : {};
  } catch (_) {
    return {};
  }
}
