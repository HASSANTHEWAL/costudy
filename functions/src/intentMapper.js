'use strict';

/**
 * Translation boundary between Firestore's Indonesian schema and the
 * coalition engine's neutral English shape.
 *
 * The engine (functions/src/coalitionEngine.js) is a pure algorithm: interval
 * overlap, centroid containment, greedy first fit. It deliberately knows
 * nothing about CoStudy's domain vocabulary, which is what lets it stay
 * separately testable and, later, reusable. Teaching it `idPengguna` would
 * trade that away for nothing.
 *
 * So the storage layer speaks Indonesian, matching the proposal, and this
 * module is the only place the two vocabularies meet. If a field is renamed
 * on either side, exactly one file changes.
 */

/** Firestore `suasana` -> engine `atmosphere`. */
const ATMOSPHERE_BY_SUASANA = {
  hening: 'quiet',
  diskusi: 'discussion',
  bebas: 'any',
};

/** Engine `atmosphere` -> Firestore `suasana`. */
const SUASANA_BY_ATMOSPHERE = {
  quiet: 'hening',
  discussion: 'diskusi',
  any: 'bebas',
};

/** Intent lifecycle, per proposal F.7. */
const STATUS = {
  ACTIVE: 'aktif',
  MATCHED: 'tercocokkan',
  EXPIRED: 'kedaluwarsa',
  CANCELLED: 'dibatalkan',
};

/** Coalition lifecycle. */
const COALITION_STATUS = {
  PENDING: 'menunggu',
  ACTIVE: 'aktif',
  COMPLETED: 'tuntas',
  FAILED: 'gagal',
};

/**
 * Translate one Firestore intent document into the engine's input shape.
 *
 * Returns null when the document cannot be mapped — an unknown `suasana`, or
 * a missing field. The caller drops those rather than passing half-formed
 * objects on: the engine already routes invalid input to `unmatched`, but a
 * document that fails HERE is a schema problem worth logging, not a student
 * whose window happened not to overlap with anyone.
 *
 * @param {string} id Firestore document id
 * @param {object} data Firestore document data (Indonesian field names)
 * @returns {object|null} engine-shaped intent, or null if unmappable
 */
function toEngineIntent(id, data) {
  if (!data || typeof data !== 'object') return null;

  const atmosphere = ATMOSPHERE_BY_SUASANA[data.suasana];
  if (atmosphere === undefined) return null;

  if (typeof data.idPengguna !== 'string') return null;
  if (!Number.isFinite(data.waktuMulai) || !Number.isFinite(data.waktuSelesai)) {
    return null;
  }
  if (!Number.isFinite(data.lat) || !Number.isFinite(data.lng)) return null;
  if (!Number.isFinite(data.radiusM)) return null;

  return {
    id,
    userId: data.idPengguna,
    startTime: data.waktuMulai,
    endTime: data.waktuSelesai,
    lat: data.lat,
    lng: data.lng,
    radiusM: data.radiusM,
    // The engine only ever considers 'active'. Callers pass documents already
    // filtered to status === 'aktif', so this is a constant rather than a
    // translation of whatever was stored.
    atmosphere,
    status: 'active',
  };
}

module.exports = {
  toEngineIntent,
  ATMOSPHERE_BY_SUASANA,
  SUASANA_BY_ATMOSPHERE,
  STATUS,
  COALITION_STATUS,
};
