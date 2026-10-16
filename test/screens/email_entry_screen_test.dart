import 'package:costudy/auth/auth_service.dart';
import 'package:costudy/screens/email_entry_screen.dart';
import 'package:costudy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Client-side rejection, exercised through the actual widget.
///
/// These cases never reach Firebase: the screen checks the address locally and
/// stops before calling AuthService, which is why a bare AuthService (whose
/// FirebaseAuth is resolved lazily) is safe to hand it here. Anything that
/// would send a link belongs in an integration test against the emulator.
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    // The default 800x600 test surface is wider and shorter than any phone,
    // and the branded header pushes the submit button past 600px. Use the
    // design's own canvas size so the layout under test is the real one.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCoStudyTheme(),
        home: EmailEntryScreen(authService: AuthService()),
      ),
    );
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Kirim tautan verifikasi');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField), email);
    await tapSubmit(tester);
  }

  testWidgets('shows the near-miss message for a UII staff address',
      (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'dosen@uii.ac.id');

    expect(
      find.textContaining('bukan alamat mahasiswa'),
      findsOneWidget,
      reason: 'the most common mistake deserves the most specific message',
    );
  });

  testWidgets('rejects a consumer address', (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'nada@gmail.com');

    expect(find.textContaining('hanya untuk mahasiswa UII'), findsOneWidget);
  });

  testWidgets('rejects a lookalike domain that merely contains the campus one',
      (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'nada@students.uii.ac.id.evil.com');

    expect(find.textContaining('hanya untuk mahasiswa UII'), findsOneWidget);
  });

  testWidgets('rejects an empty submission', (tester) async {
    await pumpScreen(tester);
    await tapSubmit(tester);

    expect(find.text('Alamat email belum diisi.'), findsOneWidget);
  });

  testWidgets('clears the error as soon as the student starts correcting it',
      (tester) async {
    await pumpScreen(tester);
    await submit(tester, 'nada@gmail.com');
    expect(find.textContaining('hanya untuk mahasiswa UII'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nada@gmail.co');
    await tester.pump();

    expect(
      find.textContaining('hanya untuk mahasiswa UII'),
      findsNothing,
      reason: 'leaving the error up while they type reads as nagging',
    );
  });
}
