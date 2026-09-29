import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../providers/config_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/response_providers.dart';
import '../../widgets/common.dart';
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

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _info = p);
    });
    Permission.notification.status.then((s) {
      if (mounted) setState(() => _notifGranted = s.isGranted);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tetapan')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Paparan
              const SectionLabel('Paparan'),
              AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingRow(
                        icon: LucideIcons.eyeOff,
                        title: 'Tema',
                        subtitle: 'Mod gelap ialah lalai',
                        trailing: SegmentedButton<AppThemeMode>(
                          segments: const [
                            ButtonSegment(value: AppThemeMode.dark, label: Text('Gelap')),
                            ButtonSegment(value: AppThemeMode.light, label: Text('Terahang')),
                            ButtonSegment(value: AppThemeMode.system, label: Text('Sistem')),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) =>
                              ref.read(settingsProvider.notifier).setThemeMode(s.first),
                        ),
                      ),
                      const Divider(height: 24),
                      _SettingRow(
                        icon: LucideIcons.smartphone,
                        title: 'Orientasi',
                        subtitle: 'Auto mengikut sensor (disyorkan)',
                        trailing: SegmentedButton<OrientationSetting>(
                          segments: const [
                            ButtonSegment(value: OrientationSetting.auto, label: Text('Auto')),
                            ButtonSegment(value: OrientationSetting.portrait, label: Text('Potret')),
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

              // Notifikasi
              const SectionLabel('Notifikasi'),
              AppCard(
                child: ListTile(
                  leading: const Icon(LucideIcons.info),
                  title: const Text('Kebenaran notifikasi'),
                  subtitle: Text(
                    _notifGranted == null
                        ? 'Menyemak...'
                        : (_notifGranted!
                            ? 'Dibenarkan — progres hantaran dipaparkan'
                            : 'Tidak dibenarkan — hantaran tetap berjalan tanpa notifikasi'),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      final s = await Permission.notification.request();
                      setState(() => _notifGranted = s.isGranted);
                    },
                    child: const Text('Benarkan'),
                  ),
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
                      title: const Text('Kosongkan log respons'),
                      subtitle: const Text('Buang semua entri respons dalam memori'),
                      onTap: () {
                        ref.read(responseLogProvider.notifier).clear();
                        showAppSnackBar(context, 'Log respons dikosongkan.');
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(LucideIcons.trash2, color: AppColors.danger),
                      title: const Text('Kosongkan sejarah & gagal',
                          style: TextStyle(color: AppColors.danger)),
                      subtitle: const Text('Padam semua rekod sesi dan kegagalan'),
                      onTap: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Padam semua rekod?',
                          message: 'Sejarah dan rekod gagal akan dipadam secara kekal.',
                        );
                        if (ok) {
                          await ref.read(historyProvider.notifier).clearAll();
                          await ref.read(failedProvider.notifier).clearAll();
                          if (context.mounted) {
                            showAppSnackBar(context, 'Semua rekod dipadam.');
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Panduan
              const SectionLabel('Panduan'),
              AppCard(
                child: ListTile(
                  leading: const Icon(LucideIcons.keyboard),
                  title: const Text('Papar panduan permulaan'),
                  subtitle: const Text('Cara dapat webhook, token bot & pilih folder'),
                  onTap: () {
                    ref.read(settingsProvider.notifier).resetOnboarding();
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const _OnboardingHost(),
                    ));
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Tentang
              const SectionLabel('Tentang'),
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
                        'Versi ${_info?.version ?? '-'} (${_info?.buildNumber ?? '-'})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.shieldCheck, size: 14, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'Token disimpan dalam stor selamat • Tiada telemetri',
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
