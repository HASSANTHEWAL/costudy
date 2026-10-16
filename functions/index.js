'use strict';

/**
 * CoStudy — Cloud Functions entry point.
 *
 * Thin wiring only. Every decision lives in src/ as a plain function so it can
 * be tested without an emulator; this file attaches those functions to
 * Firebase triggers, sets deployment options, and translates domain errors
 * into the wire format Firebase Authentication expects.
 *
 * This is the ONLY file in the codebase that imports firebase-functions. Keep
 * it that way — see the note at the top of src/authBlocking.js.
 */

const { beforeUserCreated, beforeUserSignedIn, HttpsError } = require('firebase-functions/v2/identity');
const { setGlobalOptions } = require('firebase-functions/v2');

const {
  handleBeforeUserCreated,
  handleBeforeUserSignedIn,
  CampusAuthError,
} = require('./src/authBlocking');

/**
 * Jakarta. The pilot population is entirely in Yogyakarta, and blocking
 * functions sit in the critical path of every sign-in — a round trip to
 * us-central1 would be felt on the sign-in screen.
 *
 * maxInstances caps runaway cost on the Firebase free tier (proposal C.4).
 */
setGlobalOptions({ region: 'asia-southeast2', maxInstances: 10 });

/**
 * Adapt a pure handler to a Firebase blocking trigger.
 *
 * `invalid-argument` is the right code for a rejected address: the request is
 * well formed, the address just is not one we accept. Firebase surfaces the
 * message to the client.
 *
 * Anything that is not a CampusAuthError is a bug, not a policy decision, and
 * is rethrown untouched so it surfaces as a genuine 500 in Cloud Logging
 * rather than being disguised as a validation failure.
 */
function toBlockingHandler(handle) {
  return (event) => {
    try {
      return handle(event);
    } catch (error) {
      if (error instanceof CampusAuthError) {
        throw new HttpsError('invalid-argument', error.message);
      }
      throw error;
    }
  };
}

/** FR-01 — no non-student account is ever created. */
exports.enforceCampusDomainOnCreate = beforeUserCreated(
  toBlockingHandler(handleBeforeUserCreated),
);

/** FR-01, NFR-03 — re-checked on every sign-in; issues the campusVerified claim. */
exports.enforceCampusDomainOnSignIn = beforeUserSignedIn(
  toBlockingHandler(handleBeforeUserSignedIn),
);
