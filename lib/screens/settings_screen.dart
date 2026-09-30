import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/secure_store.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/response_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/update_service.dart';
import '../../widgets/common.dart';
import 'update_dialog.dart';
import 'onboarding_screen.dart';

/// Skrin Tetapan — tema, orientasi, notifikasi, data & tentang.
/// Kandungan dihadkan ~560dp dan dipusatkan pada skrin lebar.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _info;
  bool? _notifGranted;
  bool? _batteryIgnored;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _info = p);
    });
    Permission.notification.status.then((s) {
      if (mounted) setState(() => _notifGranted = s.isGranted);
    });
    // 2f: keadaan pengecualian bateri semasa — dipapar pada baris Tetapan.
    Permission.ignoreBatteryOptimizations.status.then((s) {
      if (mounted) setState(() => _batteryIgnored = s.isGranted);
    }).catchError((_) {
      if (mounted) setState(() => _batteryIgnored = false);
    });
  }

  /// 1b: semakan manual — melaporkan keputusan (up to date / update
  /// available / gagal). Mengabaikan throttle 6 jam & versi dilangkau.
  Future<void> _checkForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = _info ?? await PackageInfo.fromPlatform();
      final result =
          await UpdateService.checkLatest(currentVersion: info.version);
      if (!mounted) return;
      if (!result.ok) {
        showAppSnackBar(context, result.error ?? 'Check failed.', error: true);
        return;
      }
      if (!result.updateAvailable || result.release == null) {
        showAppSnackBar(
            context, 'You are on the latest version (${info.version}).');
        return;
      }
      await showUpdateAvailableDialog(
        context,
        release: result.release!,
        currentVersion: info.version,
        // 3c: semasa sesi hantaran aktif, Update now dilumpuhkan.
        sessionRunning: () =>
            ref.read(uploadControllerProvider).isRunning,
      );
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Check failed.', error: true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Display
              const SectionLabel('Display'),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingRow(
                        icon: LucideIcons.eyeOff,
                        title: 'Theme',
                        subtitle: 'Dark mode is the default',
                        trailing: SegmentedButton<AppThemeMode>(
                          segments: const [
                            ButtonSegment(value: AppThemeMode.dark, label: Text('Dark')),
                            ButtonSegment(value: AppThemeMode.light, label: Text('Light')),
                            ButtonSegment(value: AppThemeMode.system, label: Text('System')),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) =>
                              ref.read(settingsProvider.notifier).setThemeMode(s.first),
                        ),
                      ),
                      const Divider(height: 24),
                      _SettingRow(
                        icon: LucideIcons.smartphone,
                        title: 'Orientation',
                        subtitle: 'Follow the sensor automatically (recommended)',
                        trailing: SegmentedButton<OrientationSetting>(
                          segments: const [
                            ButtonSegment(value: OrientationSetting.auto, label: Text('Auto')),
                            ButtonSegment(value: OrientationSetting.portrait, label: Text('Portrait')),
                            ButtonSegment(value: OrientationSetting.landscape, label: Text('Landscape')),
                          ],
                          selected: {settings.orientation},
                          onSelectionChanged: (s) =>
                              ref.read(settingsProvider.notifier).setOrientation(s.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // B02: had saiz muat naik aktif.
              const SectionLabel('Upload limit'),
              AppCard(
                child: _SettingRow(
                  icon: LucideIcons.hardDrive,
                  title: 'Max file size per upload',
                  subtitle: 'Files larger than the limit are skipped. '
                      'Discord allows up to 100 MB on boosted servers.',
                  trailing: SegmentedButton<int>(
                    segments: [
                      for (final mb in AppLimits.fileSizePresetsMB)
                        ButtonSegment(value: mb, label: Text('$mb')),
                    ],
                    selected: {settings.maxFileMB},
                    onSelectionChanged: (s) => ref
                        .read(settingsProvider.notifier)
                        .setMaxFileMB(s.first),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Notifications
              const SectionLabel('Notifications'),
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(LucideIcons.info),
                      title: const Text('Notification permission'),
                      subtitle: Text(
                        _notifGranted == null
                            ? 'Checking...'
                            : (_notifGranted!
                                ? 'Granted — send progress is displayed'
                                : 'Not granted — sending still runs without notifications'),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          final s = await Permission.notification.request();
                          setState(() => _notifGranted = s.isGranted);
                        },
                        child: const Text('Allow'),
                      ),
                    ),
                    const Divider(height: 1),
                    // B15 + 2f: pengecualian pengoptimuman bateri — hantaran
                    // panjang lebih dipercayai di latar belakang. Keadaan
                    // semasa dipapar; boleh diminta semula di sini.
                    ListTile(
                      leading: const Icon(LucideIcons.batteryCharging),
                      title: const Text('Battery optimization'),
                      subtitle: Text(
                        _batteryIgnored == null
                            ? 'Checking...'
                            : (_batteryIgnored!
                                ? 'Unrestricted — long uploads are reliable'
                                : 'Restricted — background uploads may be paused by the system'),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          try {
                            final s = await Permission
                                .ignoreBatteryOptimizations
                                .request();
                            if (mounted) {
                              setState(() => _batteryIgnored = s.isGranted);
                            }
                          } catch (_) {}
                        },
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Data
              const SectionLabel('Data'),
              AppCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(LucideIcons.terminal),
                      title: const Text('Clear response log'),
                      subtitle: const Text('Discard all in-memory response entries'),
                      onTap: () {
                        ref.read(responseLogProvider.notifier).clear();
                        showAppSnackBar(context, 'Response log cleared.');
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(LucideIcons.trash2, color: AppColors.danger),
                      title: const Text('Clear history & failures',
                          style: TextStyle(color: AppColors.danger)),
                      subtitle: const Text('Delete all session and failure records'),
                      onTap: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Delete all records?',
                          message: 'History and failure records will be permanently deleted.',
                        );
                        if (ok) {
                          await ref.read(historyProvider.notifier).clearAll();
                          await ref.read(failedProvider.notifier).clearAll();
                          if (context.mounted) {
                            showAppSnackBar(context, 'All records deleted.');
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Panduan
              const SectionLabel('Guide'),
              AppCard(
                child: ListTile(
                  leading: const Icon(LucideIcons.keyboard),
                  title: const Text('Show the getting-started guide'),
                  subtitle: const Text('How to get a webhook, bot token & pick a folder'),
                  // B14: paparan semula panduan TIDAK mengubah status
                  // onboarding (persisted/in-memory) — hanya membuka laman.
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const _OnboardingHost(),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 20),

              // B25: buang kelayakan tersimpan.
              AppCard(
                child: ListTile(
                  leading:
                      const Icon(LucideIcons.keyRound, color: AppColors.danger),
                  title: const Text('Clear saved credentials',
                      style: TextStyle(color: AppColors.danger)),
                  subtitle: const Text(
                      'Wipe webhook URL, bot token & channel selection'),
                  onTap: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Clear saved credentials?',
                      message:
                          'The webhook URL, bot token and channel selection will be '
                          'removed from secure storage. History is not touched.',
                      confirmLabel: 'Clear',
                    );
                    if (ok) {
                      await SecureStore.safeWipeAll();
                      // Reset provider kepada nilai lalai.
                      ref.read(configProvider.notifier).setMode(SendMode.webhook);
                      ref.read(configProvider.notifier).setWebhookUrl('');
                      ref.read(configProvider.notifier).setBotToken('');
                      ref.read(configProvider.notifier).setAvatarUrl('');
                      ref.read(configProvider.notifier).setBotName('');
                      ref.read(configProvider.notifier).setChannel(id: '');
                      if (context.mounted) {
                        showAppSnackBar(context, 'Saved credentials cleared.');
                      }
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Tentang
              const SectionLabel('About'),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.blurple,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(LucideIcons.send, size: 26, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text('Discord Media Sender',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        'Version ${_info?.version ?? '-'} (${_info?.buildNumber ?? '-'})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 10),
                      // 1b: semakan manual + togol automatik — di sebelah
                      // maklumat versi (diabaikan throttle & versi dilangkau).
                      FilledButton.tonalIcon(
                        onPressed: _checkingUpdate ? null : _checkForUpdates,
                        icon: _checkingUpdate
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text('Check for updates'),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Check for updates automatically'),
                        subtitle: const Text(
                            'At most once every 6 hours, from GitHub releases'),
                        value: settings.autoUpdateEnabled,
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setAutoUpdateEnabled(v),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.shieldCheck, size: 14, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'Token stored in secure storage • No telemetry',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.success,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        trailing,
      ],
    );
  }
}

/// Hos onboarding untuk paparan semula dari Tetapan.
class _OnboardingHost extends ConsumerWidget {
  const _OnboardingHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Papar onboarding sebagai halaman biasa; butang Mula kembali ke sini.
    return const OnboardingScreen(asPage: true);
  }
}
