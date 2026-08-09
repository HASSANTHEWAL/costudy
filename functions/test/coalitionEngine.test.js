'use strict';

const { formCoalitions, haversineDistanceM } = require('../src/coalitionEngine');

// ── Fixtures ────────────────────────────────────────────────────────────────
// Anchored on the UII Library, Yogyakarta — the pilot location (proposal D.5).

const LIBRARY = { lat: -7.6875, lng: 110.4139 };

/** Epoch ms for a wall-clock time on the pilot evening. */
function at(hour, minute = 0) {
  return Date.UTC(2026, 7, 10, hour, minute);
}

/**
 * A point `metres` due east of `origin`.
 *
 * Longitude degrees shrink with latitude, hence the cos factor. Only used to
 * lay out fixtures at known separations; the engine itself uses haversine.
 */
function eastOf(origin, metres) {
  const metresPerDegreeLng = 111320 * Math.cos((origin.lat * Math.PI) / 180);
  return { lat: origin.lat, lng: origin.lng + metres / metresPerDegreeLng };
}

/** An intent that satisfies every constraint unless a field is overridden. */
function intent(overrides = {}) {
  return {
    id: 'i1',
    userId: 'u1',
    startTime: at(18),
    endTime: at(21),
    lat: LIBRARY.lat,
    lng: LIBRARY.lng,
    radiusM: 1000,
    atmosphere: 'any',
    status: 'active',
    ...overrides,
  };
}

// ── Sanity check on the fixture helper ──────────────────────────────────────

describe('fixture geometry', () => {
  it('places points at the requested separation', () => {
    const far = eastOf(LIBRARY, 1000);
    const distance = haversineDistanceM(LIBRARY.lat, LIBRARY.lng, far.lat, far.lng);
    expect(distance).toBeGreaterThan(995);
    expect(distance).toBeLessThan(1005);
  });
});

// ── Case classes from proposal E.4 ──────────────────────────────────────────

describe('formCoalitions', () => {
  it('1. forms no coalition when time windows do not overlap', () => {
    const morning = intent({ id: 'i-morning', userId: 'u-a', startTime: at(8), endTime: at(11) });
    const evening = intent({ id: 'i-evening', userId: 'u-b', startTime: at(18), endTime: at(21) });

    const { coalitions, unmatched } = formCoalitions([morning, evening]);

    expect(coalitions).toHaveLength(0);
    expect(unmatched.sort()).toEqual(['i-evening', 'i-morning']);
  });

  it('1b. forms no coalition when overlap is shorter than the minimum', () => {
    // 18:00-19:30 against 19:00-21:00 — they meet, but for only 30 minutes.
    const early = intent({ id: 'i-early', userId: 'u-a', startTime: at(18), endTime: at(19, 30) });
    const late = intent({ id: 'i-late', userId: 'u-b', startTime: at(19), endTime: at(21) });

    const { coalitions, unmatched } = formCoalitions([early, late]);

    expect(coalitions).toHaveLength(0);
    expect(unmatched.sort()).toEqual(['i-early', 'i-late']);
  });

  it('2. leaves a lone intent unmatched rather than emitting a coalition', () => {
    const { coalitions, unmatched } = formCoalitions([intent({ id: 'i-alone' })]);

    expect(coalitions).toHaveLength(0);
    expect(unmatched).toEqual(['i-alone']);
  });

  it('3. forms one coalition when the threshold is met exactly', () => {
    const first = intent({ id: 'i-hassan', userId: 'u-hassan' });
    const second = intent({
      id: 'i-laraib',
      userId: 'u-laraib',
      startTime: at(18, 30),
      endTime: at(21, 30),
      ...eastOf(LIBRARY, 200),
    });

    const { coalitions, unmatched } = formCoalitions([first, second]);

    expect(unmatched).toEqual([]);
    expect(coalitions).toHaveLength(1);

    const [coalition] = coalitions;
    expect(coalition.size).toBe(2);
    expect(coalition.intentIds.sort()).toEqual(['i-hassan', 'i-laraib']);
    expect(coalition.userIds.sort()).toEqual(['u-hassan', 'u-laraib']);
    // Common window is the intersection, 18:30-21:00 — not either member's own.
    expect(coalition.startTime).toBe(at(18, 30));
    expect(coalition.endTime).toBe(at(21));
    expect(coalition.durationMinutes).toBe(150);
    expect(coalition.atmosphere).toBe('any');
  });

  it('4. splits candidates exceeding capacity, with no group over the limit', () => {
    const seven = Array.from({ length: 7 }, (_, index) =>
      intent({ id: `i-${index}`, userId: `u-${index}` }),
    );

    const { coalitions, unmatched } = formCoalitions(seven, { maxCapacity: 5 });

    expect(unmatched).toEqual([]);
    expect(coalitions).toHaveLength(2);
    expect(coalitions.map((c) => c.size)).toEqual([5, 2]);
    for (const coalition of coalitions) {
      expect(coalition.size).toBeLessThanOrEqual(5);
    }

    // Everybody is placed, and nobody is placed twice.
    const placed = coalitions.flatMap((c) => c.intentIds);
    expect(placed).toHaveLength(7);
    expect(new Set(placed).size).toBe(7);
  });

  it('5. forms no coalition when atmosphere preferences conflict', () => {
    const quiet = intent({ id: 'i-quiet', userId: 'u-a', atmosphere: 'quiet' });
    const talkative = intent({ id: 'i-discussion', userId: 'u-b', atmosphere: 'discussion' });

    const { coalitions, unmatched } = formCoalitions([quiet, talkative]);

    expect(coalitions).toHaveLength(0);
    expect(unmatched.sort()).toEqual(['i-discussion', 'i-quiet']);
  });

  it("5b. lets 'any' join a quiet group and locks the group to quiet", () => {
    // Arrival order matters here, and equal start times are broken by id — so
    // the ids are numbered to pin the order the scenario describes.
    const quiet = intent({ id: 'i-1-quiet', userId: 'u-a', atmosphere: 'quiet' });
    const flexible = intent({ id: 'i-2-any', userId: 'u-b', atmosphere: 'any' });
    const talkative = intent({ id: 'i-3-discussion', userId: 'u-c', atmosphere: 'discussion' });

    const { coalitions, unmatched } = formCoalitions([quiet, flexible, talkative]);

    expect(coalitions).toHaveLength(1);
    expect(coalitions[0].atmosphere).toBe('quiet');
    expect(coalitions[0].intentIds.sort()).toEqual(['i-1-quiet', 'i-2-any']);
    expect(unmatched).toEqual(['i-3-discussion']);
  });

  it('6. forms no coalition when the meeting point falls outside one radius', () => {
    // 1 km apart, so the centroid sits 500 m from each. The first member would
    // travel that far; the second would not, and vetoes the group alone.
    const generous = intent({ id: 'i-generous', userId: 'u-a', radiusM: 2000 });
    const homebody = intent({
      id: 'i-homebody',
      userId: 'u-b',
      radiusM: 200,
      ...eastOf(LIBRARY, 1000),
    });

    const { coalitions, unmatched } = formCoalitions([generous, homebody]);

    expect(coalitions).toHaveLength(0);
    expect(unmatched.sort()).toEqual(['i-generous', 'i-homebody']);
  });

  it('7. never places one user in two coalitions over the same hours', () => {
    // u-shared registers twice for overlapping evenings. Only the first can
    // be honoured; the second expires silently.
    const sharedFirst = intent({ id: 'i-shared-1', userId: 'u-shared', startTime: at(18), endTime: at(20, 30) });
    const sharedSecond = intent({ id: 'i-shared-2', userId: 'u-shared', startTime: at(18, 15), endTime: at(20, 45) });
    const other = intent({ id: 'i-other', userId: 'u-other', startTime: at(18), endTime: at(20, 30) });
    const third = intent({ id: 'i-third', userId: 'u-third', startTime: at(18, 15), endTime: at(20, 45) });

    const { coalitions, unmatched } = formCoalitions([sharedFirst, sharedSecond, other, third]);

    expect(unmatched).toEqual(['i-shared-2']);
    expect(coalitions).toHaveLength(1);
    expect(coalitions[0].intentIds.sort()).toEqual(['i-other', 'i-shared-1', 'i-third']);

    // The invariant itself, stated independently of which group won.
    const appearances = coalitions.flatMap((c) => c.userIds).filter((id) => id === 'u-shared');
    expect(appearances).toHaveLength(1);
  });

  it('7b. allows one user two coalitions when the time ranges do not overlap', () => {
    const afternoon = intent({ id: 'i-pm-1', userId: 'u-shared', startTime: at(13), endTime: at(16) });
    const afternoonPeer = intent({ id: 'i-pm-2', userId: 'u-a', startTime: at(13), endTime: at(16) });
    const evening = intent({ id: 'i-eve-1', userId: 'u-shared', startTime: at(18), endTime: at(21) });
    const eveningPeer = intent({ id: 'i-eve-2', userId: 'u-b', startTime: at(18), endTime: at(21) });

    const { coalitions, unmatched } = formCoalitions([afternoon, afternoonPeer, evening, eveningPeer]);

    expect(unmatched).toEqual([]);
    expect(coalitions).toHaveLength(2);
    for (const coalition of coalitions) {
      expect(coalition.userIds).toContain('u-shared');
    }
  });
});

// ── Input handling ──────────────────────────────────────────────────────────

describe('input handling', () => {
  it('ignores intents that are not active', () => {
    const active = intent({ id: 'i-active', userId: 'u-a' });
    const matched = intent({ id: 'i-matched', userId: 'u-b', status: 'matched' });
    const expired = intent({ id: 'i-expired', userId: 'u-c', status: 'expired' });
    const cancelled = intent({ id: 'i-cancelled', userId: 'u-d', status: 'cancelled' });

    const { coalitions, unmatched } = formCoalitions([active, matched, expired, cancelled]);

    // Only the active intent is the engine's business, and alone it cannot
    // reach the threshold.
    expect(coalitions).toHaveLength(0);
    expect(unmatched).toEqual(['i-active']);
  });

  it('returns empty results for empty or missing input', () => {
    expect(formCoalitions([])).toEqual({ coalitions: [], unmatched: [] });
    expect(formCoalitions(undefined)).toEqual({ coalitions: [], unmatched: [] });
  });

  it('routes malformed intents to unmatched instead of throwing', () => {
    const good = intent({ id: 'i-good', userId: 'u-a' });
    const alsoGood = intent({ id: 'i-also-good', userId: 'u-b' });
    const broken = { id: 'i-broken', userId: 'u-c', startTime: at(18) };

    const { coalitions, unmatched } = formCoalitions([good, alsoGood, broken]);

    expect(coalitions).toHaveLength(1);
    expect(unmatched).toEqual(['i-broken']);
  });

  it('is deterministic regardless of input ordering', () => {
    const intents = Array.from({ length: 6 }, (_, index) =>
      intent({ id: `i-${index}`, userId: `u-${index}`, startTime: at(18, index) }),
    );

    const forward = formCoalitions(intents, { maxCapacity: 4 });
    const reversed = formCoalitions([...intents].reverse(), { maxCapacity: 4 });

    expect(reversed).toEqual(forward);
  });
});

// ── Configuration ───────────────────────────────────────────────────────────

describe('options', () => {
  it('honours a raised minimum threshold', () => {
    const pair = [
      intent({ id: 'i-a', userId: 'u-a' }),
      intent({ id: 'i-b', userId: 'u-b' }),
    ];

    expect(formCoalitions(pair).coalitions).toHaveLength(1);

    const strict = formCoalitions(pair, { minThreshold: 3 });
    expect(strict.coalitions).toHaveLength(0);
    expect(strict.unmatched.sort()).toEqual(['i-a', 'i-b']);
  });

  it('honours a relaxed minimum overlap', () => {
    const early = intent({ id: 'i-early', userId: 'u-a', startTime: at(18), endTime: at(19, 30) });
    const late = intent({ id: 'i-late', userId: 'u-b', startTime: at(19), endTime: at(21) });

    expect(formCoalitions([early, late]).coalitions).toHaveLength(0);

    const relaxed = formCoalitions([early, late], { minOverlapMinutes: 30 });
    expect(relaxed.coalitions).toHaveLength(1);
    expect(relaxed.coalitions[0].durationMinutes).toBe(30);
  });
});
