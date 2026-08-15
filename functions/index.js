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
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');
const { logger } = require('firebase-functions');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

const {
  handleBeforeUserCreated,
  handleBeforeUserSignedIn,
  CampusAuthError,
} = require('./src/authBlocking');
const { matchAndNotify } = require('./src/matchAndNotify');

initializeApp();

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

/**
 * FR-04/05/06 — the matching run.
 *
 * Every five minutes rather than on intent creation. Matching is inherently a
 * batch problem: a coalition is a property of the whole set of open intents,
 * and running on each write would repeatedly evaluate an incomplete set and
 * form small coalitions that a moment's patience would have made larger. The
 * interval is also what gives an unmatched intent repeated chances across the
 * life of its window instead of one.
 *
 * All logic lives in src/matchAndNotify.js so it can be tested without
 * deploying; this wrapper only supplies the SDK handles and logs the outcome.
 */
exports.runCoalitionMatcher = onSchedule(
  {
    schedule: 'every 5 minutes',
    // Matching reasons about wall-clock windows students entered locally.
    timeZone: 'Asia/Jakarta',
    // One run at a time. Two overlapping passes could read the same 'aktif'
    // intents and form two coalitions from the same students.
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    const summary = await matchAndNotify(getFirestore(), getMessaging());
    logger.info('coalition matcher run complete', summary);
  },
);
