import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'providers/config_providers.dart';
import 'root_shell.dart';
import 'screens/onboarding_screen.dart';

/// Akar aplikasi — tema adaptif + gerbang onboarding.
class DmsApp extends ConsumerStatefulWidget {
  const DmsApp({super.key});

  @override
  ConsumerState<DmsApp> createState() => _DmsAppState();
}

class _DmsAppState extends ConsumerState<DmsApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Gunakan orientasi pilihan pengguna selepas muat.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOrientation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _applyOrientation() {
    final o = ref.read(settingsProvider).orientation;
    _setOrientation(o);
  }

  static Future<void> _setOrientation(OrientationSetting o) async {
    switch (o) {
      case OrientationSetting.auto:
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case OrientationSetting.portrait:
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
      case OrientationSetting.landscape:
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // Terapkan orientasi apabila tetapan berubah.
    ref.listen<SettingsState>(settingsProvider, (prev, next) {
      if (prev?.orientation != next.orientation) _setOrientation(next.orientation);
    });

    return MaterialApp(
      title: 'Discord Media Sender',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: settings.onboardingDone ? const RootShell() : const OnboardingScreen(),
    );
  }
}
