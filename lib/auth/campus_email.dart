/// Campus email domain verification (FR-01) — client side.
///
/// This is a deliberate mirror of `functions/src/emailDomain.js`. The two
/// copies must agree, and the Dart tests in `test/auth/campus_email_test.dart`
/// mirror the Jest cases so drift shows up as a failing test rather than as a
/// student being rejected by the server after the client said they were fine.
///
/// This copy is a COURTESY: it renders a helpful inline error before the user
/// submits, saving a round trip. The Cloud Function is the one that enforces
/// (NFR-03). A pass here is never authorisation.
library;

/// The only domain that identifies a UII student. Exact match, not a suffix.
const String kCampusDomain = 'students.uii.ac.id';

/// UII's general domain — staff, faculty, alumni. Recognised only to give a
/// better error message.
const String kInstitutionDomain = 'uii.ac.id';

/// Why an address was refused.
///
/// Distinct cases rather than one generic failure, because the design brief
/// asks for an inline error that is "helpful, not scolding" — and that needs
/// to know which mistake was made.
enum CampusEmailRejection {
  missing,
  malformed,
  uiiNonStudent,
  notCampus,
  aliasNotAllowed,
}

/// Indonesian user-facing copy. Warm, plain, never blames the user.
///
/// Kept byte-identical to MESSAGES in emailDomain.js so the student sees the
/// same words whether the client or the server refused them.
const Map<CampusEmailRejection, String> _messages = {
  CampusEmailRejection.missing: 'Alamat email belum diisi.',
  CampusEmailRejection.malformed:
      'Format email belum benar. Contoh: nama@students.uii.ac.id',
  CampusEmailRejection.uiiNonStudent:
      'Sepertinya itu alamat UII, tapi bukan alamat mahasiswa. '
          'Gunakan @students.uii.ac.id.',
  CampusEmailRejection.notCampus:
      'CoStudy hanya untuk mahasiswa UII. Gunakan email @students.uii.ac.id.',
  CampusEmailRejection.aliasNotAllowed:
      'Gunakan alamat email kampus utamamu, tanpa tanda tambah (+).',
};

/// Outcome of checking one address.
class CampusEmailResult {
  const CampusEmailResult._({
    required this.valid,
    this.reason,
    this.message,
    this.email,
    this.canonicalEmail,
    this.localPart,
    this.domain,
  });

  factory CampusEmailResult._reject(CampusEmailRejection reason) =>
      CampusEmailResult._(
        valid: false,
        reason: reason,
        message: _messages[reason],
      );

  final bool valid;
  final CampusEmailRejection? reason;

  /// Student-facing text, ready to render. Null when [valid].
  final String? message;

  /// The address as typed, trimmed and lowercased. Null when invalid.
  final String? email;

  /// Stable identity key with any plus-tag removed. Use this, not [email],
  /// when asking whether an account already exists for a person.
  final String? canonicalEmail;

  final String? localPart;
  final String? domain;
}

/// Strip a plus-address tag: `nada+skripsi` -> `nada`.
///
/// Dots are deliberately NOT stripped. Gmail treats `n.a.d.a` and `nada` as
/// one mailbox, but that is a Google convention rather than a rule of email,
/// and assuming it for a domain we do not control risks collapsing two real
/// students into a single identity.
String canonicalizeLocalPart(String localPart) {
  final plusIndex = localPart.indexOf('+');
  return plusIndex == -1 ? localPart : localPart.substring(0, plusIndex);
}

/// Pragmatic shape check — deliberately not an RFC 5322 parser.
///
/// Full RFC compliance permits addresses no campus issues, and the well-known
/// "validating" regexes are unreadable and still wrong. What actually guards
/// the door is the exact domain match in [verifyCampusEmail]; this only has to
/// reject obvious nonsense first.
({String localPart, String domain})? _splitEmail(String normalized) {
  if (RegExp(r'\s').hasMatch(normalized)) return null;

  final parts = normalized.split('@');
  if (parts.length != 2) return null;

  final localPart = parts[0];
  final domain = parts[1];
  if (localPart.isEmpty || domain.isEmpty) return null;

  for (final segment in [localPart, domain]) {
    if (segment.startsWith('.') ||
        segment.endsWith('.') ||
        segment.contains('..')) {
      return null;
    }
  }

  if (!domain.contains('.')) return null;

  return (localPart: localPart, domain: domain);
}

/// Verify that [rawEmail] belongs to a UII student.
///
/// [allowPlusAddressing] defaults to false. Plus-addressing would let one
/// mailbox mint unlimited accounts, undermining NFR-03 and inflating the
/// pilot's registered-student count (proposal C.2). Institutional addresses
/// do not use plus-tags, so refusing them costs almost nothing.
///
/// [campusDomain] is overridable so tests, and a future multi-campus phase
/// (proposal C.4), are not stuck with one hardcoded university.
CampusEmailResult verifyCampusEmail(
  String? rawEmail, {
  bool allowPlusAddressing = false,
  String campusDomain = kCampusDomain,
}) {
  if (rawEmail == null || rawEmail.trim().isEmpty) {
    return CampusEmailResult._reject(CampusEmailRejection.missing);
  }

  // Domains are case-insensitive, and local parts are case-sensitive in theory
  // but never in practice at any provider a campus would use.
  final normalized = rawEmail.trim().toLowerCase();
  final target = campusDomain.toLowerCase();

  final parsed = _splitEmail(normalized);
  if (parsed == null) {
    return CampusEmailResult._reject(CampusEmailRejection.malformed);
  }

  final localPart = parsed.localPart;
  final domain = parsed.domain;

  if (domain != target) {
    // A staff, faculty, or departmental address is a near miss worth naming
    // precisely — the student is at the right university, wrong address.
    // Checked as a suffix so fkip.uii.ac.id is caught too, but only after the
    // exact student-domain match above has already failed. Note this does NOT
    // match students.uii.ac.id.evil.com, whose real domain is evil.com.
    final isInstitution = domain == kInstitutionDomain ||
        domain.endsWith('.$kInstitutionDomain');
    return CampusEmailResult._reject(
      isInstitution
          ? CampusEmailRejection.uiiNonStudent
          : CampusEmailRejection.notCampus,
    );
  }

  if (!allowPlusAddressing && localPart.contains('+')) {
    return CampusEmailResult._reject(CampusEmailRejection.aliasNotAllowed);
  }

  final canonicalLocalPart = canonicalizeLocalPart(localPart);

  return CampusEmailResult._(
    valid: true,
    email: normalized,
    canonicalEmail: '$canonicalLocalPart@$domain',
    localPart: canonicalLocalPart,
    domain: domain,
  );
}
