import 'package:discord_media_sender/screens/update_dialog.dart';
import 'package:discord_media_sender/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GithubRelease _release() => const GithubRelease(
      tagName: 'v1.0.10',
      body: '### Kemas Kini\n- FIX sesuatu\n- NEW sesuatu lain',
      htmlUrl: 'https://github.com/tukiza7-debug/discord-media-sender/releases/tag/v1.0.10',
      assets: [],
    );

Widget _host(UpdateAvailableDialog dialog) => MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => dialog,
            ),
            child: const Text('open'),
          ),
        );
      })),
    );

Future<void> _open(WidgetTester tester, UpdateAvailableDialog dialog) async {
  await tester.pumpWidget(_host(dialog));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dialog memaparkan versi, nota & TIGA butang (1c)', (tester) async {
    await _open(
      tester,
      UpdateAvailableDialog(
        release: _release(),
        currentVersion: '1.0.9',
        sessionRunning: () => false,
      ),
    );
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.0.9'), findsOneWidget);
    expect(find.textContaining('1.0.10'), findsWidgets);
    expect(find.textContaining('FIX sesuatu'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
  });

  testWidgets('SESI AKTIF: Update now dilumpuhkan + penjelasan dipapar (1c/3c)',
      (tester) async {
    await _open(
      tester,
      UpdateAvailableDialog(
        release: _release(),
        currentVersion: '1.0.9',
        sessionRunning: () => true,
      ),
    );
    expect(find.textContaining('upload session is running'),
        findsOneWidget); // penjelasan ringkas
    final updateBtn = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Update now'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(updateBtn.onPressed, isNull); // dilumpuhkan
  });

  testWidgets('TIADA SESI: Update now boleh ditekan', (tester) async {
    await _open(
      tester,
      UpdateAvailableDialog(
        release: _release(),
        currentVersion: '1.0.9',
        sessionRunning: () => false,
      ),
    );
    final updateBtn = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Update now'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(updateBtn.onPressed, isNotNull);
  });

  testWidgets('nota panjang dipotong pada had (1c)', (tester) async {
    final longBody = 'x' * 10000;
    await _open(
      tester,
      UpdateAvailableDialog(
        release: GithubRelease(
          tagName: 'v1.0.10',
          body: longBody,
          htmlUrl: 'https://github.com/x/y',
          assets: const [],
        ),
        currentVersion: '1.0.9',
        sessionRunning: () => false,
      ),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    // Had 5000 + penanda potongan.
    expect(text.data!.length, lessThan(5100));
    expect(text.data!.endsWith('…'), isTrue);
  });

  testWidgets('Skip this version menutup dialog tanpa memasang', (tester) async {
    var updated = false;
    await _open(
      tester,
      UpdateAvailableDialog(
        release: _release(),
        currentVersion: '1.0.9',
        sessionRunning: () => false,
        updateRunner: (onProgress, token) async {
          updated = true;
          return const UpdateFlowResult(ok: true);
        },
      ),
    );
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(updated, isFalse); // Later tidak memulakan muat turun
  });
}
