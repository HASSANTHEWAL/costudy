import 'package:costudy/intent/study_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// The client-side half of intent validation.
///
/// These rules are duplicated in firestore.rules, which is the enforcement
/// point — this copy only saves a round trip and gives the student a sentence
/// instead of PERMISSION_DENIED. The emulator suite
/// (functions/test/firestore.rules.test.js) covers the server side.
void main() {
  final start = DateTime(2026, 8, 11, 18);

  IntentValidation check({
    DateTime? startTime,
    DateTime? endTime,
    double? lat = -7.6875,
    double? lng = 110.4139,
    int radiusM = 1000,
  }) {
    return IntentValidation.check(
      startTime: startTime ?? start,
      endTime: endTime ?? start.add(const Duration(hours: 3)),
      lat: lat,
      lng: lng,
      radiusM: radiusM,
    );
  }

  group('IntentValidation', () {
    test('accepts a well-formed window', () {
      expect(check().isValid, isTrue);
    });

    test('requires both times', () {
      // Called directly rather than through check(): its `?? start` default
      // would swallow an explicitly passed null and silently test nothing.
      expect(
        IntentValidation.check(
          startTime: null,
          endTime: start.add(const Duration(hours: 3)),
          lat: -7.6875,
          lng: 110.4139,
          radiusM: 1000,
        ).isValid,
        isFalse,
      );
      expect(
        IntentValidation.check(
          startTime: start,
          endTime: null,
          lat: -7.6875,
          lng: 110.4139,
          radiusM: 1000,
        ).isValid,
        isFalse,
      );
    });

    test('rejects an end at or before the start', () {
      expect(check(endTime: start).isValid, isFalse);
      expect(
        check(endTime: start.subtract(const Duration(hours: 1))).isValid,
        isFalse,
      );
    });

    test('rejects a window shorter than the engine could ever match', () {
      // The coalition engine requires 60 minutes of overlap, so a 59-minute
      // intent is guaranteed to expire unmatched. Refusing it up front beats
      // accepting it and going quiet.
      expect(
        check(endTime: start.add(const Duration(minutes: 59))).isValid,
        isFalse,
      );
      expect(
        check(endTime: start.add(const Duration(minutes: 60))).isValid,
        isTrue,
      );
    });

    test('requires a location fix', () {
      expect(check(lat: null).isValid, isFalse);
      expect(check(lng: null).isValid, isFalse);
      expect(check(lat: null).message, contains('lokasi'));
    });

    test('rejects an out-of-range radius', () {
      expect(check(radiusM: 0).isValid, isFalse);
      expect(check(radiusM: 5001).isValid, isFalse);
      expect(check(radiusM: 2000).isValid, isTrue);
    });
  });

  group('StudyIntent serialisation', () {
    test('writes the exact key set firestore.rules allows', () {
      final intent = StudyIntent(
        userId: 'uid-alice',
        startTime: start,
        endTime: start.add(const Duration(hours: 3)),
        lat: -7.6875,
        lng: 110.4139,
        radiusM: 1000,
        atmosphere: Atmosphere.quiet,
      );

      final data = intent.toFirestore();

      // hasOnly() in the rules means an extra key is a rejected write, so the
      // key set is part of the contract, not an implementation detail.
      expect(
        data.keys.toSet(),
        {
          'userId',
          'startTime',
          'endTime',
          'lat',
          'lng',
          'radiusM',
          'atmosphere',
          'status',
          'createdAt',
        },
      );
    });

    test('stores times as epoch milliseconds for the coalition engine', () {
      final intent = StudyIntent(
        userId: 'uid-alice',
        startTime: start,
        endTime: start.add(const Duration(hours: 3)),
        lat: -7.6875,
        lng: 110.4139,
        radiusM: 1000,
        atmosphere: Atmosphere.any,
      );

      final data = intent.toFirestore();

      expect(data['startTime'], start.millisecondsSinceEpoch);
      expect(data['startTime'], isA<int>());
      expect(data['endTime'], isA<int>());
    });

    test('always opens an intent as active', () {
      // Only the engine may advance status; the rules reject anything else on
      // create.
      final data = StudyIntent(
        userId: 'uid-alice',
        startTime: start,
        endTime: start.add(const Duration(hours: 3)),
        lat: -7.6875,
        lng: 110.4139,
        radiusM: 1000,
        atmosphere: Atmosphere.discussion,
      ).toFirestore();

      expect(data['status'], 'active');
    });

    test('atmosphere wire values match the engine and the rules', () {
      expect(Atmosphere.quiet.wireValue, 'quiet');
      expect(Atmosphere.discussion.wireValue, 'discussion');
      expect(Atmosphere.any.wireValue, 'any');
    });

    test('round-trips through Firestore form', () {
      final original = StudyIntent(
        userId: 'uid-alice',
        startTime: start,
        endTime: start.add(const Duration(hours: 3)),
        lat: -7.6875,
        lng: 110.4139,
        radiusM: 2000,
        atmosphere: Atmosphere.discussion,
      );

      final data = Map<String, Object?>.from(original.toFirestore())
        // createdAt is a server sentinel on write; Firestore returns a real
        // value on read, and fromFirestore does not consume it.
        ..remove('createdAt');

      final restored = StudyIntent.fromFirestore(data);

      expect(restored.userId, original.userId);
      expect(restored.startTime, original.startTime);
      expect(restored.endTime, original.endTime);
      expect(restored.radiusM, original.radiusM);
      expect(restored.atmosphere, original.atmosphere);
      expect(restored.status, IntentStatus.active);
    });
  });
}
