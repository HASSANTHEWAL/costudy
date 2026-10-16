'use strict';

/**
 * CoStudy — session completion (FR-08).
 *
 * A coalition becomes 'tuntas' once enough of its members have confirmed
 * attendance. "Enough" is the coalition's own `ambangMinimum`, the same
 * threshold it was formed under — not a new number invented here. That
 * matters: the assurance contract promised the session would happen if the
 * threshold was met, so the threshold is what decides it happened.
 *
 * Plain async function taking `db`, for the same reason as matchAndNotify:
 * index.js wraps it in the Firestore trigger, and the Jest suite drives it
 * with a fake. Nothing here reaches for firebase-admin on its own.
 */

const CONFIRMED = 'hadir';
const COMPLETED = 'tuntas';

/**
 * Re-evaluate one coalition after a member document changed.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} idKoalisi
 * @returns {Promise<{updated: boolean, confirmed: number, threshold: number|null, reason?: string}>}
 */
async function completeCoalitionIfReady(db, idKoalisi) {
  if (typeof idKoalisi !== 'string' || idKoalisi.length === 0) {
    return { updated: false, confirmed: 0, threshold: null, reason: 'no-id' };
  }

  const coalitionRef = db.collection('coalitions').doc(idKoalisi);
  const coalitionSnap = await coalitionRef.get();

  if (!coalitionSnap.exists) {
    return { updated: false, confirmed: 0, threshold: null, reason: 'missing' };
  }

  const coalition = coalitionSnap.data() ?? {};

  // Only an active session can complete. Re-running on an already-'tuntas'
  // coalition must be a no-op: Firestore triggers are at-least-once, so this
  // function will be invoked more than once for the same write, and a second
  // update would rewrite history for no reason.
  if (coalition.status !== 'aktif') {
    return {
      updated: false,
      confirmed: 0,
      threshold: coalition.ambangMinimum ?? null,
      reason: `status-${coalition.status}`,
    };
  }

  const threshold = coalition.ambangMinimum;
  if (!Number.isFinite(threshold)) {
    return { updated: false, confirmed: 0, threshold: null, reason: 'no-threshold' };
  }

  const confirmedSnap = await db
    .collection('coalitionMembers')
    .where('idKoalisi', '==', idKoalisi)
    .where('statusKonfirmasi', '==', CONFIRMED)
    .get();

  const confirmed = confirmedSnap.size;

  if (confirmed < threshold) {
    // Below the threshold the coalition simply stays active. Nothing is
    // written and nobody is told — the same silence the matcher uses for an
    // unmatched intent, and for the same reason.
    return { updated: false, confirmed, threshold };
  }

  await coalitionRef.update({
    status: COMPLETED,
    waktuTuntas: Date.now(),
  });

  return { updated: true, confirmed, threshold };
}

module.exports = {
  completeCoalitionIfReady,
  CONFIRMED,
  COMPLETED,
};
