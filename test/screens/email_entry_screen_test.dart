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
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCoStudyTheme(),
        home: EmailEntryScreen(authService: AuthService()),
      ),
    );
  }

  Future<void> submit(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField), email);
    await tester.tap(find.text('Kirim tautan verifikasi'));
    await tester.pump();
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
    await tester.tap(find.text('Kirim tautan verifikasi'));
    await tester.pump();

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
