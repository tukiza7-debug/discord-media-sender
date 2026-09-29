import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:discord_media_sender/widgets/common.dart';
import 'package:discord_media_sender/models/models.dart';
import 'package:discord_media_sender/widgets/json_view.dart';

void main() {
  setUpAll(() {
    // Elak akses rangkaian semasa ujian widget.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('EmptyState memaparkan tajuk & sari kata', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox,
            title: 'No history yet',
            subtitle: 'Send something to see Discord responses here.',
          ),
        ),
      ),
    );
    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('Send something to see Discord responses here.'), findsOneWidget);
  });

  testWidgets('StatusBadge memaparkan kod status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: LogStatus.success, statusCode: 200),
        ),
      ),
    );
    expect(find.text('200'), findsOneWidget);
  });

  testWidgets('JsonView memaparkan JSON & boleh dilipat', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: JsonView(json: {'message': 'Success', 'code': 0}, initiallyExpanded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RESPONSE BODY (JSON)'), findsOneWidget);
    expect(find.textContaining('Success'), findsOneWidget);
  });
}
