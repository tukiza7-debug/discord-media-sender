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
///
/// Fix paparan landscape: pada skrin landscape (lebar >= 600dp tetapi
/// tinggi pendek ~360-430dp), rail kini boleh discrol (scroll down/up)
/// dan beralih ke mod padat supaya ikon Tetapan sentiasa terlihat.
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
                child: AppNavRail(selectedIndex: index, onSelect: select),
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

/// Rail navigasi adaptif tinggi — membaiki paparan landscape.
///
/// Masalah: dengan 5 destinasi berlabel + logo, rail perlukan ~450dp
/// tinggi; skrin landscape telefon hanya ~360-430dp → destinasi
/// "Tetapan" di bawah terpotong dan tidak boleh dicapai (tiada skrol).
///
/// Penyelesaian (dua lapis):
/// 1. `scrollable: true` — kumpulan destinasi boleh discrol ke atas/bawah
///    apabila tinggi tidak cukup (jaminan mutlak semua boleh dicapai).
/// 2. Mod padat pada skrin pendek (`labelType.selected`) — label hanya
///    pada tab terpilih supaya kelima-lima destinasi muat tanpa skrol
///    pada kebanyakan telefon landscape. Skrin tinggi kekal berlabel penuh.
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key, required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Tinggi minimum (dp) untuk label penuh; bawahnya guna mod padat.
  static const double _fullLabelMinHeight = 480;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < _fullLabelMinHeight;

    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelect,
      // Mod padat pada skrin landscape pendek — semua destinasi muat.
      labelType: compact
          ? NavigationRailLabelType.selected
          : NavigationRailLabelType.all,
      // Kunci fix landscape: kandungan rail boleh discrol bila tak cukup tinggi.
      scrollable: true,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.xs),
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
        for (final d in RootShell._destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.icon),
            label: Text(d.label),
          ),
      ],
    );
  }
}
