import 'package:costudy/auth/campus_email.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors functions/test/emailDomain.test.js case for case.
///
/// The validation logic exists twice — once in Dart for inline form feedback,
/// once in JavaScript for server-side enforcement. Duplication like that
/// drifts silently unless something forces it not to. These tests are that
/// something: if you change a rule in one language, change it in the other and
/// update both suites together.
void main() {
  group('accepts', () {
    test('a plain student address', () {
      final result = verifyCampusEmail('nada@students.uii.ac.id');

      expect(result.valid, isTrue);
      expect(result.email, 'nada@students.uii.ac.id');
      expect(result.canonicalEmail, 'nada@students.uii.ac.id');
      expect(result.localPart, 'nada');
      expect(result.domain, 'students.uii.ac.id');
    });

    test('an address with surrounding whitespace and mixed case', () {
      final result = verifyCampusEmail('  Nada.Taufik@Students.UII.ac.id  ');

      expect(result.valid, isTrue);
      expect(result.email, 'nada.taufik@students.uii.ac.id');
    });

    test('a numeric student-number address', () {
      expect(verifyCampusEmail('25523274@students.uii.ac.id').valid, isTrue);
    });

    test('dots in the local part, without collapsing them', () {
      final result = verifyCampusEmail('nada.taufik@students.uii.ac.id');

      expect(result.valid, isTrue);
      expect(result.canonicalEmail, 'nada.taufik@students.uii.ac.id');
    });
  });

  group('rejects as missing', () {
    for (final input in <String?>[null, '', '   ']) {
      final label = input == null ? 'null' : '"$input"';
      test(label, () {
        final result = verifyCampusEmail(input);

        expect(result.valid, isFalse);
        expect(result.reason, CampusEmailRejection.missing);
        expect(result.message, isNotEmpty);
      });
    }
  });

  group('rejects as malformed', () {
    const cases = {
      'no @': 'nadastudents.uii.ac.id',
      'two @': 'nada@nada@students.uii.ac.id',
      'empty local part': '@students.uii.ac.id',
      'empty domain': 'nada@',
      'internal whitespace': 'na da@students.uii.ac.id',
      'leading dot in local part': '.nada@students.uii.ac.id',
      'trailing dot in local part': 'nada.@students.uii.ac.id',
      'consecutive dots': 'na..da@students.uii.ac.id',
      'dotless domain': 'nada@students',
    };

    cases.forEach((label, input) {
      test(label, () {
        final result = verifyCampusEmail(input);

        expect(result.valid, isFalse);
        expect(result.reason, CampusEmailRejection.malformed);
      });
    });
  });

  group('rejects UII non-student addresses with a specific reason', () {
    const cases = {
      'the staff domain': 'dosen@uii.ac.id',
      'a faculty subdomain': 'admin@fkip.uii.ac.id',
      'a subdomain of the student domain': 'nada@fk.students.uii.ac.id',
    };

    cases.forEach((label, input) {
      test(label, () {
        final result = verifyCampusEmail(input);

        expect(result.valid, isFalse);
        expect(result.reason, CampusEmailRejection.uiiNonStudent);
        // The near-miss message must name the right domain to use.
        expect(result.message, contains('students.uii.ac.id'));
      });
    });
  });

  group('rejects as not campus', () {
    const cases = {
      'a consumer address': 'nada@gmail.com',
      'another university': 'nada@students.ugm.ac.id',
      'a lookalike suffix': 'nada@notuii.ac.id',
      // The attack the suffix check has to survive: the campus domain appears
      // in the string, but the real registrable domain is evil.com.
      'the student domain as a prefix': 'nada@students.uii.ac.id.evil.com',
    };

    cases.forEach((label, input) {
      test(label, () {
        final result = verifyCampusEmail(input);

        expect(result.valid, isFalse);
        expect(result.reason, CampusEmailRejection.notCampus);
      });
    });
  });

  group('plus-addressing', () {
    test('is rejected by default, to stop one mailbox minting many accounts',
        () {
      final result = verifyCampusEmail('nada+alt@students.uii.ac.id');

      expect(result.valid, isFalse);
      expect(result.reason, CampusEmailRejection.aliasNotAllowed);
    });

    test('is accepted when explicitly allowed, and canonicalised to one identity',
        () {
      final tagged = verifyCampusEmail(
        'nada+skripsi@students.uii.ac.id',
        allowPlusAddressing: true,
      );
      final plain = verifyCampusEmail('nada@students.uii.ac.id');

      expect(tagged.valid, isTrue);
      expect(tagged.email, 'nada+skripsi@students.uii.ac.id');
      // Different addresses, same person — the point of canonicalEmail.
      expect(tagged.canonicalEmail, plain.canonicalEmail);
    });

    test('canonicalises the local part independently of the domain rules', () {
      expect(canonicalizeLocalPart('nada+a+b'), 'nada');
      expect(canonicalizeLocalPart('nada'), 'nada');
      expect(canonicalizeLocalPart('+tagonly'), '');
    });
  });

  group('campusDomain override', () {
    test('supports a different university without code changes', () {
      const options = 'students.ugm.ac.id';

      expect(
        verifyCampusEmail('budi@students.ugm.ac.id', campusDomain: options).valid,
        isTrue,
      );
      expect(
        verifyCampusEmail('nada@students.uii.ac.id', campusDomain: options).valid,
        isFalse,
      );
    });
  });
}
