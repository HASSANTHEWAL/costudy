import 'package:costudy/intent/study_intent.dart';
import 'package:costudy/screens/history_screen.dart';
import 'package:costudy/screens/register_intent_screen.dart';
import 'package:costudy/screens/sessions_screen.dart';
import 'package:costudy/screens/waiting_screen.dart';
import 'package:costudy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout and copy checks for the screens that do not need a signed-in user.
///
/// These are worth having beyond "does it compile": pumping at a real phone
/// size turns a RenderFlex overflow into a test failure, which is how the
/// overflow on the sign-in screen's trust line was caught. Home, Profil and
/// the shell itself need a Firebase User and are not covered here.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: buildCoStudyTheme(), home: child),
    );
  }

  final summary = RegisteredIntentSummary(
    intentId: 'intent-1',
    startTime: DateTime(2026, 8, 11, 18),
    endTime: DateTime(2026, 8, 11, 21),
    radiusM: 1000,
    atmosphere: Atmosphere.quiet,
  );

  group('Sesi', () {
    testWidgets('shows a styled empty state, not a blank page', (tester) async {
      await pump(tester, const SessionsScreen());

      expect(find.text('Belum ada sesi terbentuk'), findsOneWidget);
      expect(find.byIcon(Icons.groups_2_outlined), findsOneWidget);
    });

    testWidgets('never reports absence as a failure', (tester) async {
      await pump(tester, const SessionsScreen());

      // Rule 2 of the design brief: no "no results", no rejection, ever.
      for (final forbidden in ['Tidak ada hasil', 'Tidak ditemukan', 'Gagal']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });
  });

  group('Riwayat', () {
    testWidgets('uses the inviting empty copy from the brief', (tester) async {
      await pump(tester, const HistoryScreen());

      expect(
        find.text('Sesi pertamamu akan muncul di sini'),
        findsOneWidget,
      );
    });

    testWidgets('shows the stat strip at zero rather than hiding it',
        (tester) async {
      await pump(tester, const HistoryScreen());

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Jam'), findsOneWidget);
      expect(find.text('Sesi'), findsOneWidget);
    });
  });

  group('Waiting', () {
    testWidgets('describes work happening, and shows the student\'s own window',
        (tester) async {
      await pump(tester, WaitingScreen(summary: summary));
      // One frame only: the rings and shimmer loop forever, so pumpAndSettle
      // would never return.
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Mencari irisan jadwal…'), findsOneWidget);
      expect(find.text('NIATMU'), findsOneWidget);
      expect(find.text('⏰ 18:00–21:00'), findsOneWidget);
      expect(find.text('📍 Dalam 1km'), findsOneWidget);
      expect(find.text('🔇 Hening'), findsOneWidget);
      expect(find.text('Batalkan niat'), findsOneWidget);
    });

    testWidgets('shows no count of other people', (tester) async {
      await pump(tester, WaitingScreen(summary: summary));
      await tester.pump(const Duration(milliseconds: 100));

      // The screen must never hint at how many others are waiting — knowing
      // that is the first-initiative risk the assurance contract removes.
      //
      // Matched as "a number followed by a word for people", not the bare
      // word: the copy legitimately contains "orang" in the privacy promise
      // ("kamu tidak akan muncul bagi orang lain"), which is the opposite of
      // a candidate count.
      final peopleCount = RegExp(r'\d+\s*(orang|teman|mahasiswa|kandidat)');
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data != null && peopleCount.hasMatch(w.data!),
        ),
        findsNothing,
      );
    });
  });

  group('Daftarkan Niat', () {
    testWidgets('renders every section of the form', (tester) async {
      await pump(tester, const RegisterIntentScreen(userId: 'uid-alice'));

      expect(find.text('Daftarkan Niat'), findsOneWidget);
      expect(find.text('JENDELA WAKTU'), findsOneWidget);
      expect(find.text('RADIUS PENCARIAN'), findsOneWidget);
      expect(find.text('SUASANA BELAJAR'), findsOneWidget);
      expect(find.text('Gunakan lokasi saya sekarang'), findsOneWidget);
    });

    testWidgets('offers all three atmospheres as cards, not a dropdown',
        (tester) async {
      await pump(tester, const RegisterIntentScreen(userId: 'uid-alice'));

      for (final option in Atmosphere.values) {
        expect(find.text(option.label), findsOneWidget);
        expect(find.text(option.description), findsOneWidget);
      }
      expect(find.byType(DropdownButton<Object>), findsNothing);
    });

    testWidgets('keeps the privacy reassurance visible on the form',
        (tester) async {
      await pump(tester, const RegisterIntentScreen(userId: 'uid-alice'));

      expect(
        find.textContaining('tidak terlihat oleh siapa pun'),
        findsOneWidget,
      );
    });

    testWidgets('refuses to submit without a location fix', (tester) async {
      await pump(tester, const RegisterIntentScreen(userId: 'uid-alice'));

      final button = find.widgetWithText(FilledButton, 'Daftarkan niat');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();

      // Times are unset too, so the earliest check fires first.
      expect(find.textContaining('waktu'), findsWidgets);
    });
  });
}
