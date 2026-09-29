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
        return 'Gelap';
      case AppThemeMode.light:
        return 'Terahang';
      case AppThemeMode.system:
        return 'Sistem';
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
        return 'Potret';
      case OrientationSetting.landscape:
        return 'Landscape';
    }
  }

  List<dynamic> get allowed {
    switch (this) {
      case OrientationSetting.auto:
        return <dynamic>['auto'];
      case OrientationSetting.portrait:
        return <dynamic>['portrait'];
      case OrientationSetting.landscape:
        return <dynamic>['landscape'];
    }
  }
}

/// Konfigurasi hantaran (disimpan dalam stor selamat).
class ConfigNotifier extends StateNotifier<SendConfig> {
  ConfigNotifier() : super(const SendConfig());

  Future<void> load() async {
    final map = await SecureStore.loadConfig();
    state = SendConfig.fromJson(map);
  }

  Future<void> _set(SendConfig next) async {
    state = next;
    final json = next.toJson();
    for (final key in json.keys) {
      await SecureStore.saveConfigField(key, json[key]?.toString() ?? '');
    }
  }

  Future<void> setMode(SendMode mode) => _set(state.copyWith(mode: mode));

  Future<void> setWebhookUrl(String v) => _set(state.copyWith(webhookUrl: v));

  Future<void> setBotName(String v) => _set(state.copyWith(botName: v));

  Future<void> setAvatarUrl(String v) => _set(state.copyWith(avatarUrl: v));

  Future<void> setBotToken(String v) => _set(state.copyWith(botToken: v));

  Future<void> setChannel({required String id, String? name}) =>
      _set(state.copyWith(channelId: id, channelName: name ?? state.channelName));

  Future<void> setChannelName(String v) => _set(state.copyWith(channelName: v));
}

final configProvider =
    StateNotifierProvider<ConfigNotifier, SendConfig>((ref) => ConfigNotifier());

/// Tetapan aplikasi (tema, orientasi, onboarding).
class SettingsState {
  const SettingsState({
    this.themeMode = AppThemeMode.dark,
    this.orientation = OrientationSetting.auto,
    this.onboardingDone = false,
    this.appVersion = '',
  });

  final AppThemeMode themeMode;
  final OrientationSetting orientation;
  final bool onboardingDone;
  final String appVersion;

  SettingsState copyWith({
    AppThemeMode? themeMode,
    OrientationSetting? orientation,
    bool? onboardingDone,
    String? appVersion,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        orientation: orientation ?? this.orientation,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        appVersion: appVersion ?? this.appVersion,
      );
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  Future<void> load() async {
    final s = await SecureStore.loadSettings();
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

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingDone: true);
    await SecureStore.setOnboardingDone();
  }

  Future<void> resetOnboarding() async {
    state = state.copyWith(onboardingDone: false);
    await SecureStore.setOnboardingDone();
    await SecureStore.saveOrientation(
        state.orientation == OrientationSetting.auto ? 'auto' : state.orientation.name);
  }
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
