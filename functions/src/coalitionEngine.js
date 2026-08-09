'use strict';

/**
 * CoStudy — Coalition Formation Engine (Phase 1)
 *
 * Pure, dependency-free module. No Firebase, no I/O, no clock reads. Every
 * function here is a deterministic transformation of plain objects, so the
 * engine can be unit tested in isolation and later called from a scheduled
 * Cloud Function without modification.
 *
 * ── OBJECTIVE FUNCTION ──────────────────────────────────────────────────────
 * Maximise the number of coalitions expected to COMPLETE — not the number of
 * pairings formed. A "match" that nobody attends is a failure, so the engine
 * optimises for groups that are actually worth travelling to and showing up
 * for. That objective is encoded in the constraints rather than in a scoring
 * pass: every constraint below exists to remove a class of session that would
 * form on paper and then fail in practice.
 *
 *   - A 15-minute overlap is a match but not a session worth crossing campus
 *     for, so MIN_OVERLAP_MINUTES rules it out.
 *   - A meeting point outside somebody's travel radius produces a no-show, so
 *     the candidate location is verified against every member individually.
 *   - Mixing a member who wants silence with one who wants to talk produces
 *     the "Inefficient Socializers" failure mode, so atmosphere is a hard
 *     constraint, not a preference weight.
 *   - A group of one is not a session, so sub-threshold groups are never
 *     emitted (the assurance contract: below the threshold, nothing happens).
 *
 * ── ASSURANCE CONTRACT ──────────────────────────────────────────────────────
 * Groups that do not reach MIN_THRESHOLD are not emitted as coalitions. Their
 * intent IDs are returned in `unmatched` so the caller can let them expire
 * silently. `unmatched` is NOT a rejection list and must never be surfaced to
 * a user as one — the user is never told that nobody matched.
 *
 * ── ALGORITHM ───────────────────────────────────────────────────────────────
 * Greedy baseline (staged approach, step 1). Sort active intents by start
 * time, then place each intent into the first existing group that accepts it,
 * else open a new group.
 *
 *   Sort:      O(k log k)
 *   Placement: O(k * g), k = intents, g = groups open at that point
 *
 * Sorting by start time means a group's members arrive in non-decreasing
 * start order, so the group's common window only ever shrinks from the left —
 * an intent that cannot reach back far enough is rejected immediately rather
 * than invalidating members already placed.
 */

/** Default minimum pairwise time overlap: the shortest session worth travelling for. */
const MIN_OVERLAP_MINUTES = 60;

/** Default assurance-contract threshold. Deliberately 2, not 3 — see proposal D.5. */
const MIN_THRESHOLD = 2;

/** Default maximum coalition size. Beyond this a study group stops being one. */
const MAX_CAPACITY = 5;

/** Mean Earth radius in metres (IUGG). */
const EARTH_RADIUS_M = 6371008.8;

const MS_PER_MINUTE = 60 * 1000;

const VALID_ATMOSPHERES = new Set(['quiet', 'discussion', 'any']);

/**
 * Great-circle distance between two points in metres.
 *
 * Haversine is well conditioned for the short distances this engine deals in
 * (a campus radius, hundreds of metres to a few kilometres).
 *
 * @param {number} lat1 @param {number} lng1 @param {number} lat2 @param {number} lng2
 * @returns {number} distance in metres
 */
function haversineDistanceM(lat1, lng1, lat2, lng2) {
  const toRad = (deg) => (deg * Math.PI) / 180;

  const phi1 = toRad(lat1);
  const phi2 = toRad(lat2);
  const deltaPhi = toRad(lat2 - lat1);
  const deltaLambda = toRad(lng2 - lng1);

  const a =
    Math.sin(deltaPhi / 2) ** 2 +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(deltaLambda / 2) ** 2;

  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/**
 * Overlap between two time ranges, in milliseconds. Negative when disjoint.
 */
function overlapMs(a, b) {
  return Math.min(a.endTime, b.endTime) - Math.max(a.startTime, b.startTime);
}

/**
 * True when two time ranges share any interior time at all.
 *
 * Used for the one-coalition-per-user rule, which is about double-booking
 * rather than session quality — so it uses bare overlap, not MIN_OVERLAP.
 * Touching endpoints (one ends exactly when the other starts) is not a clash.
 */
function rangesOverlap(a, b) {
  return overlapMs(a, b) > 0;
}

/**
 * CONSTRAINT — atmosphere compatibility.
 *
 * 'quiet' and 'discussion' are mutually exclusive; 'any' matches both. A group
 * carries the strictest preference stated by any member so far, starting at
 * 'any' (unconstrained).
 *
 * @returns {'quiet'|'discussion'|'any'|null} merged preference, or null if incompatible
 */
function mergeAtmosphere(groupAtmosphere, intentAtmosphere) {
  if (groupAtmosphere === 'any') return intentAtmosphere;
  if (intentAtmosphere === 'any') return groupAtmosphere;
  return groupAtmosphere === intentAtmosphere ? groupAtmosphere : null;
}

/**
 * Candidate meeting point for a set of members: the arithmetic centroid of
 * their origins.
 *
 * A plane approximation is used deliberately. Over a single campus the error
 * against a spherical centroid is well under a metre, and the value is only a
 * candidate — it is then verified against each member's own radius with the
 * real haversine distance, which is where correctness actually rests.
 */
function centroidOf(members) {
  let latSum = 0;
  let lngSum = 0;
  for (const member of members) {
    latSum += member.lat;
    lngSum += member.lng;
  }
  return { lat: latSum / members.length, lng: lngSum / members.length };
}

/**
 * CONSTRAINT — a candidate location exists inside EVERY member's radius.
 *
 * The centroid is checked against each member's own radiusM, not a shared
 * one. A member who will only travel 500 m vetoes a meeting point 600 m away
 * even if everybody else would happily go — because that member is the one
 * who would not show up.
 */
function locationSatisfiesAll(members) {
  const candidate = centroidOf(members);
  for (const member of members) {
    const distance = haversineDistanceM(candidate.lat, candidate.lng, member.lat, member.lng);
    if (distance > member.radiusM) return false;
  }
  return true;
}

/**
 * Whether `intent` can join `group` under every constraint simultaneously.
 *
 * Checks run cheapest-first so that the common rejections (same user, wrong
 * time) exit before any trigonometry.
 */
function groupAccepts(group, intent, options) {
  // CONSTRAINT — size within [minThreshold, maxCapacity]. Only the upper bound
  // can be enforced during placement; the lower bound is applied at emission.
  if (group.members.length >= options.maxCapacity) return false;

  // A user cannot occupy two seats in the same session.
  if (group.userIds.has(intent.userId)) return false;

  // CONSTRAINT — pairwise time overlap >= minOverlapMinutes.
  //
  // Checked against every existing member rather than against the group's
  // running intersection. For intervals on a line the two are equivalent (the
  // common intersection equals the overlap of the latest-starting and
  // earliest-ending pair), but the explicit pairwise form is what the
  // specification states and it costs nothing at coalition scale.
  const minOverlap = options.minOverlapMinutes * MS_PER_MINUTE;
  for (const member of group.members) {
    if (overlapMs(member, intent) < minOverlap) return false;
  }

  // CONSTRAINT — atmosphere compatibility.
  if (mergeAtmosphere(group.atmosphere, intent.atmosphere) === null) return false;

  // CONSTRAINT — candidate location inside every radius, re-verified for the
  // whole prospective membership. Adding a member moves the centroid, so a
  // member who was satisfied before may not be afterwards.
  return locationSatisfiesAll([...group.members, intent]);
}

/**
 * Shape check. A single malformed document should not abort a scheduled run,
 * so invalid intents are routed to `unmatched` rather than thrown on.
 */
function isValidIntent(intent) {
  return (
    intent !== null &&
    typeof intent === 'object' &&
    typeof intent.id === 'string' &&
    typeof intent.userId === 'string' &&
    Number.isFinite(intent.startTime) &&
    Number.isFinite(intent.endTime) &&
    intent.endTime > intent.startTime &&
    Number.isFinite(intent.lat) &&
    Number.isFinite(intent.lng) &&
    Number.isFinite(intent.radiusM) &&
    intent.radiusM >= 0 &&
    VALID_ATMOSPHERES.has(intent.atmosphere)
  );
}

/**
 * Form coalitions from a set of study intents.
 *
 * Only intents with `status === 'active'` are considered. Every other intent
 * is ignored entirely and does not appear in the result — it is already
 * matched, expired, or cancelled, and is not the engine's business.
 *
 * @param {Array<object>} intents
 *   Each: { id, userId, startTime, endTime, lat, lng, radiusM, atmosphere, status }
 *   with startTime/endTime as epoch milliseconds.
 * @param {object} [options]
 * @param {number} [options.minOverlapMinutes=60]
 * @param {number} [options.minThreshold=2]
 * @param {number} [options.maxCapacity=5]
 * @returns {{ coalitions: Array<object>, unmatched: string[] }}
 *   `coalitions` are groups that reached the threshold and satisfy every
 *   constraint. `unmatched` holds the IDs of active intents that did not —
 *   for silent expiry, never for display as a rejection.
 */
function formCoalitions(intents, options = {}) {
  const config = {
    minOverlapMinutes: options.minOverlapMinutes ?? MIN_OVERLAP_MINUTES,
    minThreshold: options.minThreshold ?? MIN_THRESHOLD,
    maxCapacity: options.maxCapacity ?? MAX_CAPACITY,
  };

  const unmatched = [];

  const candidates = [];
  for (const intent of Array.isArray(intents) ? intents : []) {
    if (!isValidIntent(intent)) {
      // Unusable input. Cannot match, and cannot be reported as a rejection
      // either — it expires silently like any other unmatched intent.
      if (intent && typeof intent.id === 'string') unmatched.push(intent.id);
      continue;
    }
    if (intent.status !== 'active') continue;
    candidates.push(intent);
  }

  // Sort by start time; tie-break on id so the output is deterministic for a
  // given input regardless of the caller's document ordering.
  candidates.sort((a, b) => a.startTime - b.startTime || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  /** @type {Array<{ members: object[], userIds: Set<string>, atmosphere: string }>} */
  const groups = [];

  // CONSTRAINT — a user appears in at most one coalition per overlapping time
  // range. Tracks the ranges each user has already been placed into, so a
  // second intent from the same user covering the same hours is skipped
  // outright rather than double-booking them.
  /** @type {Map<string, Array<{startTime: number, endTime: number}>>} */
  const userCommitments = new Map();

  for (const intent of candidates) {
    const committed = userCommitments.get(intent.userId) ?? [];
    if (committed.some((range) => rangesOverlap(range, intent))) {
      unmatched.push(intent.id);
      continue;
    }

    // Greedy first fit.
    let placed = false;
    for (const group of groups) {
      if (!groupAccepts(group, intent, config)) continue;
      group.members.push(intent);
      group.userIds.add(intent.userId);
      group.atmosphere = mergeAtmosphere(group.atmosphere, intent.atmosphere);
      placed = true;
      break;
    }

    if (!placed) {
      groups.push({
        members: [intent],
        userIds: new Set([intent.userId]),
        atmosphere: intent.atmosphere,
      });
    }

    committed.push({ startTime: intent.startTime, endTime: intent.endTime });
    userCommitments.set(intent.userId, committed);
  }

  // Emission. The assurance contract is applied here: a group that never
  // reached the threshold produces nothing at all.
  //
  // Note for the refinement stage (proposal F.6 step 2): intents freed by a
  // dropped sub-threshold group are not re-offered to other groups. Under
  // first-fit they were already rejected by every group that existed when
  // they were placed, but a later group could in principle have taken them.
  // Recovering those is a local-search improvement, not a greedy-baseline one.
  const coalitions = [];
  for (const group of groups) {
    if (group.members.length < config.minThreshold) {
      for (const member of group.members) unmatched.push(member.id);
      continue;
    }
    coalitions.push(buildCoalition(group, coalitions.length + 1, config));
  }

  return { coalitions, unmatched };
}

/**
 * Materialise an accepted group into the coalition record the rest of the
 * system consumes.
 *
 * `startTime`/`endTime` are the group's common window — the span every member
 * can actually attend — not any individual member's window.
 */
function buildCoalition(group, sequence, config) {
  const { members } = group;
  const location = centroidOf(members);

  let startTime = -Infinity;
  let endTime = Infinity;
  for (const member of members) {
    startTime = Math.max(startTime, member.startTime);
    endTime = Math.min(endTime, member.endTime);
  }

  return {
    id: `coalition-${sequence}`,
    intentIds: members.map((member) => member.id),
    userIds: members.map((member) => member.userId),
    startTime,
    endTime,
    durationMinutes: (endTime - startTime) / MS_PER_MINUTE,
    lat: location.lat,
    lng: location.lng,
    atmosphere: group.atmosphere,
    size: members.length,
    minThreshold: config.minThreshold,
    maxCapacity: config.maxCapacity,
  };
}

module.exports = {
  formCoalitions,
  haversineDistanceM,
  MIN_OVERLAP_MINUTES,
  MIN_THRESHOLD,
  MAX_CAPACITY,
};
