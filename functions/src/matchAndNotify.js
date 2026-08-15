'use strict';

/**
 * CoStudy — the matching run (FR-04, FR-05, FR-06).
 *
 * Plain async function taking `db` and `messaging` as arguments rather than a
 * Cloud Function. That is the whole reason it is testable: index.js wraps it
 * in a scheduler trigger, and the Jest suite drives it with fakes. Nothing in
 * here reaches for firebase-admin on its own.
 *
 * ── THE TWO RULES THAT SHAPE THIS FILE ──────────────────────────────────────
 *
 * 1. SIMULTANEOUS REVELATION. Every member of a coalition learns about it at
 *    the same moment. Nobody is told "someone is interested, do you accept?"
 *    — that would recreate the asymmetry (one person exposed, one deciding)
 *    that the assurance contract exists to remove. Hence: one multicast, sent
 *    after the write lands, never a per-member sequence of invitations.
 *
 * 2. SILENT EXPIRY. An intent that finds nobody is marked 'kedaluwarsa' and
 *    NOTHING is sent. No "we couldn't find anyone", no "try again", no
 *    consolation. The student is never informed they were passed over,
 *    because being passed over is precisely the experience this product
 *    removes. This is a hard design requirement, not a nicety — see the
 *    assertion in the test suite.
 */

const { formCoalitions } = require('./coalitionEngine');
const { toEngineIntent, STATUS, COALITION_STATUS } = require('./intentMapper');

/** Assurance-contract threshold: below this, nothing happens at all. */
const MIN_THRESHOLD = 2;

/**
 * Arithmetic centroid of the members' origins — the coalition's meeting point.
 *
 * The engine has already proven this point falls inside every member's own
 * radius, so it is a location all of them agreed to travel to by registering
 * the radius they did.
 */
function centroidOf(members) {
  let lat = 0;
  let lng = 0;
  for (const member of members) {
    lat += member.lat;
    lng += member.lng;
  }
  return { lat: lat / members.length, lng: lng / members.length };
}

/**
 * Run one matching pass.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {import('firebase-admin/messaging').Messaging} messaging
 * @param {object} [options]
 * @param {number} [options.now] epoch ms, injectable so expiry is testable
 * @returns {Promise<object>} a summary for logging
 */
async function matchAndNotify(db, messaging, options = {}) {
  const now = options.now ?? Date.now();

  // (a) Every open intent. The Admin SDK bypasses security rules, which is
  // what makes this cross-user read possible at all — no client can do it.
  const snapshot = await db
    .collection('intents')
    .where('status', '==', STATUS.ACTIVE)
    .get();

  /** @type {Map<string, object>} engine intent id -> original Firestore data */
  const sourceById = new Map();
  const engineIntents = [];
  const unmappable = [];

  snapshot.forEach((doc) => {
    const mapped = toEngineIntent(doc.id, doc.data());
    if (mapped === null) {
      // A schema problem, not a matching outcome. Logged, and deliberately
      // left 'aktif' so it is visible rather than quietly expired.
      unmappable.push(doc.id);
      return;
    }
    sourceById.set(doc.id, doc.data());
    engineIntents.push(mapped);
  });

  // (b) The algorithm itself, untouched and unaware of any of the above.
  const { coalitions, unmatched } = formCoalitions(engineIntents, {
    minThreshold: MIN_THRESHOLD,
  });

  const formed = [];
  for (const coalition of coalitions) {
    // Defence in depth. The engine already refuses to emit anything below the
    // threshold; asserting it again here means a future change to the engine
    // cannot silently start writing one-person "coalitions", which would be
    // the assurance contract failing in the most damaging possible way.
    if (coalition.size < MIN_THRESHOLD) continue;

    const result = await writeCoalition(db, coalition, engineIntents);
    formed.push(result);

    // Notification happens AFTER the batch commits. If the write fails, the
    // students are never told about a session that does not exist.
    await notifyMembers(db, messaging, result);
  }

  // (d) Silent expiry.
  const expired = await expireStaleIntents(db, unmatched, sourceById, now);

  return {
    intentsConsidered: engineIntents.length,
    unmappable,
    coalitionsFormed: formed.length,
    membersNotified: formed.reduce((sum, f) => sum + f.tokens.length, 0),
    intentsExpired: expired,
  };
}

/**
 * Write one coalition, its member records, and the intent status changes — in
 * a single batch.
 *
 * Atomicity matters here specifically: a coalition doc without its members, or
 * intents left 'aktif' after being matched, would let the next run five
 * minutes later match the same students into a second coalition.
 */
async function writeCoalition(db, coalition, engineIntents) {
  const byId = new Map(engineIntents.map((intent) => [intent.id, intent]));
  const members = coalition.intentIds.map((id) => byId.get(id));

  const location = centroidOf(members);
  const coalitionRef = db.collection('coalitions').doc();
  const batch = db.batch();

  batch.set(coalitionRef, {
    waktuTerbentuk: Date.now(),
    lokasiFinal: { lat: location.lat, lng: location.lng },
    waktuMulai: coalition.startTime,
    waktuSelesai: coalition.endTime,
    ambangMinimum: MIN_THRESHOLD,
    jumlahAnggota: coalition.size,
    // 'aktif' rather than 'menunggu': by the time this document exists the
    // coalition is a fact the members are about to be told about, not a
    // proposal awaiting anyone's approval. Nobody invited anybody.
    status: COALITION_STATUS.ACTIVE,
  });

  for (const member of members) {
    // Deterministic id — firestore.rules proves membership with a single
    // exists() on exactly this path, instead of needing a query.
    const memberRef = db
      .collection('coalitionMembers')
      .doc(`${coalitionRef.id}_${member.userId}`);

    batch.set(memberRef, {
      idKoalisi: coalitionRef.id,
      idPengguna: member.userId,
      statusKonfirmasi: 'menunggu',
      statusKehadiran: 'belum',
    });

    batch.update(db.collection('intents').doc(member.id), {
      status: STATUS.MATCHED,
    });
  }

  await batch.commit();

  return {
    coalitionId: coalitionRef.id,
    userIds: members.map((m) => m.userId),
    intentIds: members.map((m) => m.id),
    size: coalition.size,
    tokens: [],
  };
}

/**
 * Notify every member of a newly formed coalition, simultaneously.
 *
 * A member with no FCM token is skipped rather than treated as a failure:
 * they simply have not granted notification permission yet, and their session
 * still exists and still appears in the app. Failing the run over it would
 * punish the other members for one person's settings.
 */
async function notifyMembers(db, messaging, coalition) {
  const tokens = [];

  for (const userId of coalition.userIds) {
    let snapshot;
    try {
      snapshot = await db.collection('users').doc(userId).get();
    } catch (error) {
      continue;
    }
    if (!snapshot || !snapshot.exists) continue;

    const token = snapshot.data()?.fcmToken;
    if (typeof token === 'string' && token.length > 0) tokens.push(token);
  }

  coalition.tokens = tokens;
  if (tokens.length === 0) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification: {
      title: 'Sesi Ditemukan! 🎯',
      body: 'Sesi belajar siap dimulai.',
    },
    data: {
      type: 'session_found',
      coalitionId: coalition.coalitionId,
    },
  });
}

/**
 * Mark unmatched intents whose window has already closed as 'kedaluwarsa'.
 *
 * NO notification is sent, ever. See rule 2 at the top of this file.
 *
 * Intents whose window is still open are left alone — they remain 'aktif' and
 * are reconsidered on the next run, which is the entire reason the scheduler
 * repeats every five minutes rather than running once.
 */
async function expireStaleIntents(db, unmatchedIds, sourceById, now) {
  const stale = unmatchedIds.filter((id) => {
    const data = sourceById.get(id);
    return data && Number.isFinite(data.waktuSelesai) && data.waktuSelesai < now;
  });

  if (stale.length === 0) return 0;

  const batch = db.batch();
  for (const id of stale) {
    batch.update(db.collection('intents').doc(id), {
      status: STATUS.EXPIRED,
    });
  }
  await batch.commit();

  return stale.length;
}

module.exports = {
  matchAndNotify,
  centroidOf,
  MIN_THRESHOLD,
};
