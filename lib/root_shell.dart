import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core/app_theme.dart';
import 'providers/config_providers.dart';
import 'screens/history/history_screen.dart';
import 'screens/responses/responses_screen.dart';
import 'screens/send/send_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/failed/failed_screen.dart';

/// Cangkang navigasi utama — adaptif:
/// - lebar < 600dp: NavigationBar bawah, satu lajur
/// - lebar >= 600dp: NavigationRail kiri
class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  static const _destinations = [
    (icon: LucideIcons.send, label: 'Hantar'),
    (icon: LucideIcons.messageSquare, label: 'Respons'),
    (icon: LucideIcons.history, label: 'Sejarah'),
    (icon: LucideIcons.alertTriangle, label: 'Gagal'),
    (icon: LucideIcons.settings, label: 'Tetapan'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppBreakpoints.compact;

    final screens = const [
      SendScreen(),
      ResponsesScreen(),
      HistoryScreen(),
      FailedScreen(),
      SettingsScreen(),
    ];

    void select(int i) {
      if (i == index) return;
      HapticFeedback.selectionClick();
      ref.read(tabIndexProvider.notifier).state = i;
    }

    final body = wide
        ? Row(
            children: [
              SizedBox(
                width: 88,
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg, top: AppSpacing.sm),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.blurple,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Icon(LucideIcons.send, size: 19, color: Colors.white),
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(index: index, children: screens),
              ),
            ],
          )
        : Scaffold(
            body: IndexedStack(index: index, children: screens),
            bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: select,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.icon),
                    label: d.label,
                  ),
              ],
            ),
          );

    if (wide) return Scaffold(body: body);
    return body;
  }
}
