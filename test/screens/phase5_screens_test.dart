import 'package:costudy/coalition/coalition.dart';
import 'package:costudy/coalition/place_name.dart';
import 'package:costudy/profile/student_profile.dart';
import 'package:costudy/screens/history_screen.dart';
import 'package:costudy/screens/profile_setup_screen.dart';
import 'package:costudy/screens/sessions_screen.dart';
import 'package:costudy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// A resolver that never touches a platform geocoder.
///
/// Also the assertion that matters most in this file: whatever it returns, no
/// test below ever expects a number on screen.
class _FakePlaceResolver implements PlaceNameResolver {
  const _FakePlaceResolver(this.name);

  final String name;

  @override
  Future<String> describe(double lat, double lng) async => name;
}

/// Records what Profile Setup writes, without Firestore.
class _FakeProfileRepository implements ProfileRepository {
  final List<Map<String, Object?>> saves = [];

  @override
  Future<void> saveSetup({
    required String uid,
    required String nama,
    required String jurusan,
    String? emailKampus,
  }) async {
    saves.add({
      'uid': uid,
      'nama': nama,
      'jurusan': jurusan,
      'emailKampus': emailKampus,
    });
  }

  @override
  Future<StudentProfile> load(String uid) async => StudentProfile(uid: uid);

  @override
  Future<String?> jurusanOf(String uid) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CoalitionWithMembership entry({
  CoalitionStatus status = CoalitionStatus.active,
  ConfirmationStatus confirmation = ConfirmationStatus.pending,
  List<String> faculties = const ['Teknik', 'Hukum'],
  int memberCount = 2,
}) {
  return CoalitionWithMembership(
    coalition: Coalition(
      id: 'coalition-1',
      startTime: DateTime(2026, 8, 15, 19),
      endTime: DateTime(2026, 8, 15, 21),
      lat: -7.6875,
      lng: 110.4139,
      memberCount: memberCount,
      minimumThreshold: 2,
      status: status,
      faculties: faculties,
    ),
    membership: CoalitionMembership(
      id: 'coalition-1_uid-alice',
      coalitionId: 'coalition-1',
      userId: 'uid-alice',
      confirmation: confirmation,
    ),
  );
}

void main() {
  setUpAll(() async {
    // Riwayat formats dates with the Indonesian locale.
    await initializeDateFormatting('id_ID');
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: buildCoStudyTheme(), home: child),
    );
  }

  // ── Profile Setup ─────────────────────────────────────────────────────────

  group('ProfileSetupScreen', () {
    testWidgets('renders both fields', (tester) async {
      await pump(
        tester,
        ProfileSetupScreen(
          uid: 'uid-alice',
          emailKampus: 'alice@students.uii.ac.id',
          repository: _FakeProfileRepository(),
        ),
      );

      expect(find.text('NAMA LENGKAP'), findsOneWidget);
      expect(find.text('JURUSAN'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    });

    testWidgets('save is disabled until BOTH fields are filled',
        (tester) async {
      await pump(
        tester,
        ProfileSetupScreen(
          uid: 'uid-alice',
          emailKampus: 'alice@students.uii.ac.id',
          repository: _FakeProfileRepository(),
        ),
      );

      FilledButton button() =>
          tester.widget<FilledButton>(find.byType(FilledButton));

      expect(button().onPressed, isNull, reason: 'nothing filled yet');

      await tester.enterText(find.byType(TextFormField), 'Alice Rahmawati');
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'jurusan still unset');

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hukum').last);
      await tester.pumpAndSettle();

      expect(button().onPressed, isNotNull, reason: 'both fields filled');
    });

    testWidgets('writes nama and jurusan on save', (tester) async {
      final repository = _FakeProfileRepository();
      var completed = false;

      await pump(
        tester,
        ProfileSetupScreen(
          uid: 'uid-alice',
          emailKampus: 'alice@students.uii.ac.id',
          repository: repository,
          onCompleted: () => completed = true,
        ),
      );

      await tester.enterText(find.byType(TextFormField), '  Alice Rahmawati  ');
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teknik Informatika').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(repository.saves, hasLength(1));
      expect(repository.saves.single, {
        'uid': 'uid-alice',
        'nama': 'Alice Rahmawati', // trimmed
        'jurusan': 'Teknik Informatika',
        'emailKampus': 'alice@students.uii.ac.id',
      });
      expect(completed, isTrue);
    });

    testWidgets('cannot be dismissed', (tester) async {
      await pump(
        tester,
        ProfileSetupScreen(
          uid: 'uid-alice',
          emailKampus: null,
          repository: _FakeProfileRepository(),
        ),
      );

      expect(
        find.byWidgetPredicate((w) => w is PopScope && w.canPop == false),
        findsOneWidget,
      );
    });
  });

  // ── Sesi ──────────────────────────────────────────────────────────────────

  group('Sesi tab', () {
    testWidgets('shows the empty state when there is no active coalition',
        (tester) async {
      await pump(
        tester,
        const SessionsScreen(
          activeCoalitionStream: Stream<CoalitionWithMembership?>.empty(),
        ),
      );
      await tester.pump();

      expect(find.text('Belum ada sesi terbentuk'), findsOneWidget);
    });

    testWidgets('shows the session detail card when one is active',
        (tester) async {
      await pump(
        tester,
        SessionsScreen(
          activeCoalitionStream: Stream.value(entry()),
          placeResolver: const _FakePlaceResolver('Perpustakaan Pusat'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sesi terbentuk'), findsOneWidget);
      expect(find.text('19.00 – 21.00 WIB'), findsOneWidget);
      expect(find.text('Perpustakaan Pusat'), findsOneWidget);
      expect(find.text('2 mahasiswa · Teknik, Hukum'), findsOneWidget);
      expect(find.text('Konfirmasi Kehadiran'), findsOneWidget);
    });

    testWidgets('NEVER shows coordinates, even when geocoding fails',
        (tester) async {
      await pump(
        tester,
        SessionsScreen(
          activeCoalitionStream: Stream.value(entry()),
          // The real resolver's failure path returns this.
          placeResolver: const _FakePlaceResolver(PlaceNameResolver.fallback),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sekitar kampus UII'), findsOneWidget);

      // The hard rule, asserted against every Text on screen rather than a
      // specific widget: a decimal coordinate must never reach a student.
      final coordinate = RegExp(r'-?\d+\.\d{3,}');
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data != null && coordinate.hasMatch(w.data!),
        ),
        findsNothing,
      );
    });

    testWidgets('shows the confirmed badge instead of the button once hadir',
        (tester) async {
      await pump(
        tester,
        SessionsScreen(
          activeCoalitionStream: Stream.value(
            entry(confirmation: ConfirmationStatus.attending),
          ),
          placeResolver: const _FakePlaceResolver('Perpustakaan Pusat'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sudah dikonfirmasi'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('Konfirmasi Kehadiran'), findsNothing);
    });

    testWidgets('shows the completion state when tuntas, and can dismiss it',
        (tester) async {
      await pump(
        tester,
        SessionsScreen(
          activeCoalitionStream:
              Stream.value(entry(status: CoalitionStatus.completed)),
          placeResolver: const _FakePlaceResolver('Perpustakaan Pusat'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sesi selesai — lihat riwayat kamu.'), findsOneWidget);

      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();

      expect(find.text('Belum ada sesi terbentuk'), findsOneWidget);
    });

    testWidgets('never shows a member name', (tester) async {
      await pump(
        tester,
        SessionsScreen(
          activeCoalitionStream: Stream.value(entry()),
          placeResolver: const _FakePlaceResolver('Perpustakaan Pusat'),
        ),
      );
      await tester.pumpAndSettle();

      // The card is handed faculties and a count; there is no field on
      // Coalition that could carry a name in the first place.
      expect(find.textContaining('Alice'), findsNothing);
      expect(find.textContaining('uid-'), findsNothing);
    });
  });

  // ── Riwayat ───────────────────────────────────────────────────────────────

  group('Riwayat tab', () {
    testWidgets('shows the empty state when there is no history',
        (tester) async {
      await pump(
        tester,
        const HistoryScreen(
          historyStream: Stream<List<CoalitionWithMembership>>.empty(),
        ),
      );
      await tester.pump();

      expect(
        find.text('Sesi pertamamu akan muncul di sini'),
        findsOneWidget,
      );
    });

    testWidgets('renders a list item with Indonesian date and status chip',
        (tester) async {
      await pump(
        tester,
        HistoryScreen(
          historyStream: Stream.value([
            entry(status: CoalitionStatus.completed),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sabtu, 15 Agustus 2026'), findsOneWidget);
      expect(find.text('19.00–21.00'), findsOneWidget);
      expect(find.text('Tuntas'), findsOneWidget);
      expect(find.textContaining('2 orang'), findsOneWidget);
    });

    testWidgets('counts only completed sessions in the Tuntas stat',
        (tester) async {
      await pump(
        tester,
        HistoryScreen(
          historyStream: Stream.value([
            entry(status: CoalitionStatus.completed),
            entry(status: CoalitionStatus.failed),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tuntas'), findsOneWidget, reason: 'one completed');
      expect(find.text('Gagal'), findsOneWidget);
      expect(find.text('Sesi'), findsOneWidget, reason: 'stat strip label');
    });
  });
}
