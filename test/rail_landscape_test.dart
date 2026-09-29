import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:discord_media_sender/root_shell.dart';

/// Ujian fix paparan landscape: ikon Tetapan pada NavigationRail.
///
/// Latar: pada telefon landscape (lebar >= 600dp, tinggi ~360-430dp),
/// rail dengan 5 destinasi berlabel + logo melebihi tinggi skrin dan
/// dahulunya TIDAK boleh discrol — destinasi "Tetapan" terpotong.
/// Fix: `scrollable: true` + mod padat (`labelType.selected`) pada
/// skrin pendek supaya semua destinasi terlihat & boleh disentuh.
void main() {
  Future<void> pumpRail(WidgetTester tester, Size logical) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = logical * 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 88,
                child: AppNavRail(selectedIndex: 0, onSelect: (_) {}),
              ),
              const VerticalDivider(width: 1),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'Landscape telefon (915x411): ikon Tetapan terlihat & boleh disentuh tanpa skrol',
    (tester) async {
      await pumpRail(tester, const Size(915, 411));

      final settings = find.byIcon(LucideIcons.settings);
      expect(settings, findsOneWidget);
      // Kunci fix: destinasi paling bawah kekal dalam viewport & boleh disentuh.
      expect(settings.hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'Landscape kecil (668x360): rail boleh discrol — kandungan dibalut SingleChildScrollView',
    (tester) async {
      await pumpRail(tester, const Size(668, 360));

      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
      // scrollable: true → kumpulan destinasi sentiasa boleh discrol ke
      // atas/bawah walaupun tinggi skrin sangat pendek.
      final scrollableInRail = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollableInRail, findsOneWidget);
    },
  );

  testWidgets(
    'Landscape (844x390): mod padat — kelima-lima destinasi muat dalam viewport',
    (tester) async {
      await pumpRail(tester, const Size(844, 390));

      // Ikon Tetapan (destinasi paling bawah) berada dalam skrin tanpa perlu skrol.
      final settings = tester.getRect(find.byIcon(LucideIcons.settings));
      expect(settings.bottom, lessThan(390));
      expect(find.byIcon(LucideIcons.settings).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'Landscape sangat pendek (620x320): boleh discrol ke bawah — Tetapan capai selepas skrol',
    (tester) async {
      await pumpRail(tester, const Size(620, 320));

      expect(find.byIcon(LucideIcons.settings), findsOneWidget);

      // Skrol ke bawah (arah negatif) pada kandungan rail.
      await tester.drag(find.byType(NavigationRail), const Offset(0, -80));
      await tester.pumpAndSettle();

      // Selepas skrol, ikon Tetapan kini terlihat & boleh disentuh.
      expect(find.byIcon(LucideIcons.settings).hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'Skrin tinggi (411x915 potret): label penuh kelima-lima destinasi',
    (tester) async {
      await pumpRail(tester, const Size(411, 915));

      for (final label in ['Send', 'Responses', 'History', 'Failed', 'Settings']) {
        expect(find.text(label), findsOneWidget, reason: 'Label $label hilang');
      }
      expect(find.byIcon(LucideIcons.settings).hitTestable(), findsOneWidget);
    },
  );
}
