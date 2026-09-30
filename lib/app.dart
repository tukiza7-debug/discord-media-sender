import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/app_theme.dart';
import 'providers/config_providers.dart';
import 'providers/upload_providers.dart';
import 'screens/update_dialog.dart';
import 'services/foreground_manager.dart';
import 'services/update_service.dart';
import 'root_shell.dart';
import 'screens/onboarding_screen.dart';

/// Akar aplikasi — tema adaptif + gerbang onboarding + 2c/2d (reattach,
/// prompt "Resume sending?") + 1b (semakan kemas kini automatik).
class DmsApp extends ConsumerStatefulWidget {
  const DmsApp({super.key});

  @override
  ConsumerState<DmsApp> createState() => _DmsAppState();
}

class _DmsAppState extends ConsumerState<DmsApp> with WidgetsBindingObserver {
  bool _promptShowing = false;
  Timer? _updateRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Gunakan orientasi pilihan pengguna selepas muat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyOrientation();
      // 2d: prompt sambung semula (senarai disediakan oleh main.dart).
      _maybeShowResumePrompt();
      // 1b: semakan kemas kini automatik selepas frame pertama — tidak
      // pernah melambatkan permulaan.
      _autoUpdateCheck();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateRetry?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 2c: sambung semula UI kepada task isolate (swipe-away & buka semula,
      // atau proses mati & servis direstasi).
      unawaited(_onAppResumed());
    }
  }

  Future<void> _onAppResumed() async {
    try {
      await ref.read(uploadControllerProvider.notifier).reattach();
    } catch (_) {}
    // 2d: sesi mungkin terputus semasa app di latar belakang.
    await _maybeShowResumePrompt(refresh: true);
    // 1b: cuba semula jika tundaan sebelum ini belum selesai.
    _autoUpdateCheck();
  }

  // ------------------------------------------------- sambung semula (2d)

  Future<void> _maybeShowResumePrompt({bool refresh = false}) async {
    if (_promptShowing || !mounted) return;
    // Jangan ganggu sesi yang sedang berjalan.
    if (ref.read(uploadControllerProvider).isRunning) return;

    var list = ref.read(resumableSessionsProvider);
    if (list.isEmpty && refresh) {
      list = await ref.read(uploadControllerProvider.notifier)
          .checkResumableSessions();
      ref.read(resumableSessionsProvider.notifier).state = list;
    }
    if (list.isEmpty || !mounted) return;
    if (ref.read(uploadControllerProvider).isRunning) return;

    final session = list.first;
    _promptShowing = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resume sending?'),
          content: Text(
            '${session.pendingCount} file(s) were left unsent because the app '
            'was closed or stopped while this session was running.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (discard == true) {
        await ref
            .read(uploadControllerProvider.notifier)
            .discardResumable(session.sessionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session discarded.')),
          );
        }
      } else {
        final result = await ref
            .read(uploadControllerProvider.notifier)
            .resumeSession(session.sessionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: result.isGood
                  ? AppColors.success
                  : AppColors.danger,
            ),
          );
        }
      }
    } finally {
      _promptShowing = false;
      // Kosongkan senarai — keputusan sudah dibuat (atau sesi telah tamat).
      final remaining = ref.read(resumableSessionsProvider);
      ref.read(resumableSessionsProvider.notifier).state = remaining
          .where((r) => r.sessionId != session.sessionId)
          .toList();
    }
  }

  // ---------------------------------------------- kemas kini (1b, 3c)

  Future<void> _autoUpdateCheck() async {
    try {
      _updateRetry?.cancel();
      _updateRetry = null;
      final settings = ref.read(settingsProvider);
      if (!settings.autoUpdateEnabled) return;
      if (!await UpdateService.isAutoCheckDue()) return;

      // 3c: jangan semak semasa sesi aktif — tunda sehingga idle.
      if (ref.read(uploadControllerProvider).isRunning ||
          await ForegroundManager.isServiceRunning()) {
        _updateRetry = Timer(const Duration(minutes: 5), () {
          if (mounted) unawaited(_autoUpdateCheck());
        });
        return;
      }

      // Catat masa semakan SELEPAS laluan tundaan — semakan tunda tidak
      // menghabiskan throttle.
      await UpdateService.markAutoChecked();
      final info = await PackageInfo.fromPlatform();
      final result = await UpdateService.checkLatest(currentVersion: info.version);
      if (!mounted) return;
      if (!result.ok || !result.updateAvailable || result.release == null) {
        return; // automatik: gagal/up-to-date — SENYAP (1a)
      }
      final skipped = await UpdateService.skippedTag();
      if (skipped == result.release!.tag) return;
      if (!mounted) return;
      await showUpdateAvailableDialog(
        context,
        release: result.release!,
        currentVersion: info.version,
        sessionRunning: () =>
            ref.read(uploadControllerProvider).isRunning,
      );
    } catch (_) {}
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
