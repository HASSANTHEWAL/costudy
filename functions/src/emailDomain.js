'use strict';

/**
 * CoStudy — Campus email domain verification (FR-01)
 *
 * Pure, dependency-free module. No Firebase, no I/O. The rules that decide
 * who counts as a UII student live here so they can be unit tested without an
 * emulator, and so the same logic can be reused by the client for inline form
 * validation and by the blocking Cloud Function for enforcement.
 *
 * The client copy is a courtesy — it exists to render a helpful error before
 * the user submits. The Cloud Function copy is the one that matters (NFR-03:
 * only verified accounts may register intent). Never treat a client-side pass
 * as authorisation.
 */

/** The only domain that identifies a UII student. Exact match, not a suffix. */
const CAMPUS_DOMAIN = 'students.uii.ac.id';

/** UII's general domain — staff, faculty, alumni. Recognised only to give a better error. */
const INSTITUTION_DOMAIN = 'uii.ac.id';

/**
 * Rejection reasons. Distinct codes rather than one generic failure, so the
 * interface can say something useful. The design brief asks for an inline
 * error that is "helpful, not scolding" — that needs to know WHY it failed.
 */
const REASONS = {
  MISSING: 'missing',
  MALFORMED: 'malformed',
  UII_NON_STUDENT: 'uii_non_student',
  NOT_CAMPUS: 'not_campus',
  ALIAS_NOT_ALLOWED: 'alias_not_allowed',
};

/** Indonesian user-facing copy. Warm, plain, and it never blames the user. */
const MESSAGES = {
  [REASONS.MISSING]: 'Alamat email belum diisi.',
  [REASONS.MALFORMED]: 'Format email belum benar. Contoh: nama@students.uii.ac.id',
  // Reached by any uii.ac.id subdomain — staff, faculty, or a departmental
  // student domain — so the wording names the address to use rather than
  // guessing which wrong one was typed.
  [REASONS.UII_NON_STUDENT]:
    'Sepertinya itu alamat UII, tapi bukan alamat mahasiswa. Gunakan @students.uii.ac.id.',
  [REASONS.NOT_CAMPUS]:
    'CoStudy hanya untuk mahasiswa UII. Gunakan email @students.uii.ac.id.',
  [REASONS.ALIAS_NOT_ALLOWED]:
    'Gunakan alamat email kampus utamamu, tanpa tanda tambah (+).',
};

/**
 * Pragmatic email shape check.
 *
 * Deliberately not an RFC 5322 parser. Full RFC compliance permits addresses
 * no campus issues and the well-known "validating" regexes are unreadable and
 * still wrong. What actually guards the door is the exact domain match below;
 * this check only needs to reject obvious nonsense before we get there.
 */
function splitEmail(normalized) {
  if (/\s/.test(normalized)) return null;

  const parts = normalized.split('@');
  if (parts.length !== 2) return null;

  const [localPart, domain] = parts;
  if (localPart.length === 0 || domain.length === 0) return null;

  // No leading/trailing/consecutive dots on either side.
  for (const segment of [localPart, domain]) {
    if (segment.startsWith('.') || segment.endsWith('.') || segment.includes('..')) {
      return null;
    }
  }

  // A domain must have at least one dot, and no stray @-adjacent punctuation.
  if (!domain.includes('.')) return null;

  return { localPart, domain };
}

/**
 * Strip a plus-address tag: `nada+skripsi` -> `nada`.
 *
 * Dots are deliberately NOT stripped. Gmail treats `n.a.d.a` and `nada` as the
 * same mailbox, but that is a Google convention, not a rule of email — and
 * assuming it for a domain we do not control risks collapsing two real
 * students into one identity. Plus-tags are safe to strip because the segment
 * after `+` is defined as a tag rather than part of the mailbox name.
 */
function canonicalizeLocalPart(localPart) {
  const plusIndex = localPart.indexOf('+');
  return plusIndex === -1 ? localPart : localPart.slice(0, plusIndex);
}

/**
 * Verify that an address belongs to a UII student.
 *
 * @param {unknown} rawEmail
 * @param {object} [options]
 * @param {boolean} [options.allowPlusAddressing=false]
 *   When false, `nada+alt@students.uii.ac.id` is rejected outright.
 *
 *   PRODUCT DECISION, not a technical one. Plus-addressing would let one
 *   student mint unlimited accounts from a single mailbox, which undermines
 *   NFR-03 and would quietly inflate the pilot's "students registered"
 *   figure (proposal C.2). Institutional addresses do not use plus-tags, so
 *   the cost of refusing them is close to zero. Flip this to true if a real
 *   student ever turns up needing one.
 * @param {string} [options.campusDomain=CAMPUS_DOMAIN]
 *   Overridable so tests and a future multi-campus phase are not stuck with
 *   a hardcoded university (proposal C.4, Phase 4).
 * @returns {{
 *   valid: boolean,
 *   reason?: string,
 *   message?: string,
 *   email?: string,
 *   canonicalEmail?: string,
 *   localPart?: string,
 *   domain?: string
 * }}
 */
function verifyCampusEmail(rawEmail, options = {}) {
  const allowPlusAddressing = options.allowPlusAddressing ?? false;
  const campusDomain = (options.campusDomain ?? CAMPUS_DOMAIN).toLowerCase();

  if (typeof rawEmail !== 'string' || rawEmail.trim() === '') {
    return reject(REASONS.MISSING);
  }

  // Domains are case-insensitive, and local parts are case-sensitive in
  // theory but never in practice at any provider a campus would use.
  const normalized = rawEmail.trim().toLowerCase();

  const parsed = splitEmail(normalized);
  if (parsed === null) return reject(REASONS.MALFORMED);

  const { localPart, domain } = parsed;

  if (domain !== campusDomain) {
    // A staff or alumni address is a near miss worth naming precisely — the
    // user is at the right university and just used the wrong address.
    // Checked as a suffix so `fkip.uii.ac.id` is caught too, but only after
    // the exact student-domain match above has already failed.
    const isInstitution =
      domain === INSTITUTION_DOMAIN || domain.endsWith(`.${INSTITUTION_DOMAIN}`);
    return reject(isInstitution ? REASONS.UII_NON_STUDENT : REASONS.NOT_CAMPUS);
  }

  if (!allowPlusAddressing && localPart.includes('+')) {
    return reject(REASONS.ALIAS_NOT_ALLOWED);
  }

  const canonicalLocalPart = canonicalizeLocalPart(localPart);

  return {
    valid: true,
    email: normalized,
    // Stable identity key. Use this, not `email`, when checking whether an
    // account already exists for a person.
    canonicalEmail: `${canonicalLocalPart}@${domain}`,
    localPart: canonicalLocalPart,
    domain,
  };
}

function reject(reason) {
  return { valid: false, reason, message: MESSAGES[reason] };
}

module.exports = {
  verifyCampusEmail,
  canonicalizeLocalPart,
  CAMPUS_DOMAIN,
  INSTITUTION_DOMAIN,
  REASONS,
  MESSAGES,
};
