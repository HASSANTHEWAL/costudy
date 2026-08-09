'use strict';

/**
 * CoStudy — Auth blocking handlers (FR-01, NFR-03)
 *
 * Server-side enforcement of "only UII students may hold an account". These
 * run inside Firebase Authentication itself, before a user record is created
 * and before each sign-in, so there is no window in which a non-student
 * account exists.
 *
 * ── WHY THIS FILE IMPORTS NOTHING FROM FIREBASE ─────────────────────────────
 * The obvious implementation throws `HttpsError` from
 * `firebase-functions/v2/identity`. That single import pulls in
 * firebase-admin -> jwks-rsa -> jose, and jose v6 is ESM-only, which Jest
 * cannot load under its CJS transform. Beyond the tooling friction it is
 * simply the wrong dependency shape: this module does string validation and
 * has no business carrying a JWT library.
 *
 * So the handlers throw `CampusAuthError`, a plain Error, and index.js
 * translates it into `HttpsError` at the trigger boundary. Same pattern as
 * the coalition engine: the decisions are pure and testable, and the Firebase
 * coupling lives in the thin wiring layer.
 */

const { verifyCampusEmail } = require('./emailDomain');

/**
 * A rejected sign-up or sign-in.
 *
 * `message` is student-facing Indonesian copy — index.js passes it straight
 * through to the client, which is why it is written for a person rather than
 * a log file. `reason` is the machine-readable code from emailDomain.
 */
class CampusAuthError extends Error {
  constructor(reason, message) {
    super(message);
    this.name = 'CampusAuthError';
    this.reason = reason;
  }
}

function deny(result) {
  throw new CampusAuthError(result.reason, result.message);
}

/**
 * beforeUserCreated — the gate.
 *
 * Runs once, before Firebase writes the user record. Throwing here means no
 * account is created at all.
 *
 * Note what this deliberately does NOT do: it does not set `emailVerified`.
 * With email-link sign-in, clicking the link is what proves the student owns
 * the mailbox, and Firebase sets that flag itself on a successful link
 * sign-in. Setting it here would assert ownership we have not observed, and
 * would hand a working account to anyone who typed a classmate's address.
 *
 * @param {{ data?: { email?: string, uid?: string } }} event
 * @returns {{ customClaims: object }}
 * @throws {CampusAuthError}
 */
function handleBeforeUserCreated(event) {
  const email = event?.data?.email;
  const result = verifyCampusEmail(email);

  if (!result.valid) deny(result);

  // Recorded at creation so later code never has to re-parse the address.
  // `campusVerified` is intentionally absent — see handleBeforeUserSignedIn.
  return {
    customClaims: {
      campus: 'uii',
      canonicalEmail: result.canonicalEmail,
    },
  };
}

/**
 * beforeUserSignedIn — the recurring check.
 *
 * Runs on every sign-in, which buys two things the creation gate cannot:
 *
 *   1. Accounts that predate a tightening of the domain rule are caught the
 *      next time they are used, rather than being grandfathered in forever.
 *   2. `campusVerified` is recomputed from the CURRENT `emailVerified` state
 *      instead of being frozen at creation.
 *
 * Point 2 is the security-relevant one. Email-link sign-in proves ownership,
 * but a project with password auth also enabled can create an account with an
 * address the user does not control — `emailVerified` stays false in that
 * case. Downstream authorisation (Firestore rules gating intent registration,
 * per NFR-03) must key off this session claim, never off mere existence of
 * the account.
 *
 * @param {{ data?: { email?: string, emailVerified?: boolean } }} event
 * @returns {{ sessionClaims: object }}
 * @throws {CampusAuthError}
 */
function handleBeforeUserSignedIn(event) {
  const email = event?.data?.email;
  const result = verifyCampusEmail(email);

  if (!result.valid) deny(result);

  return {
    sessionClaims: {
      campus: 'uii',
      canonicalEmail: result.canonicalEmail,
      // The gate for FR-02: registering an intent requires this to be true.
      // Strict identity check — a truthy string must not pass for verified.
      campusVerified: event?.data?.emailVerified === true,
    },
  };
}

module.exports = {
  handleBeforeUserCreated,
  handleBeforeUserSignedIn,
  CampusAuthError,
};
