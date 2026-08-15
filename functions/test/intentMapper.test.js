'use strict';

const {
  toEngineIntent,
  ATMOSPHERE_BY_SUASANA,
  SUASANA_BY_ATMOSPHERE,
  STATUS,
} = require('../src/intentMapper');

/**
 * The storage vocabulary is Indonesian; the coalition engine's is English.
 * This module is the only place they meet, which makes it the only place a
 * rename can silently break matching.
 *
 * The failure mode being guarded against is quiet and total: if the mapper
 * stops recognising a document, formCoalitions() receives an empty list and
 * returns zero coalitions. That is indistinguishable from "nobody's schedules
 * overlapped" — the one outcome this product must never fake.
 */

/**
 * Exactly what lib/intent/study_intent.dart writes.
 *
 * Kept as a literal rather than built from constants: if the Dart side
 * changes a key, this test must fail rather than quietly follow along.
 * `dibuatPada` is a server timestamp the mapper ignores.
 */
function flutterDocument(overrides = {}) {
  return {
    idPengguna: 'uid-alice',
    waktuMulai: Date.UTC(2026, 7, 11, 18),
    waktuSelesai: Date.UTC(2026, 7, 11, 21),
    lat: -7.6875,
    lng: 110.4139,
    radiusM: 1000,
    suasana: 'hening',
    status: 'aktif',
    dibuatPada: { seconds: 1786000000, nanoseconds: 0 },
    ...overrides,
  };
}

describe('the Flutter document maps to the engine shape', () => {
  test('every field the client writes is carried across', () => {
    const mapped = toEngineIntent('intent-1', flutterDocument());

    expect(mapped).toEqual({
      id: 'intent-1',
      userId: 'uid-alice',
      startTime: Date.UTC(2026, 7, 11, 18),
      endTime: Date.UTC(2026, 7, 11, 21),
      lat: -7.6875,
      lng: 110.4139,
      radiusM: 1000,
      atmosphere: 'quiet',
      status: 'active',
    });
  });

  test('the mapped shape is exactly what the engine validates', () => {
    // isValidIntent() in coalitionEngine.js checks these and nothing else;
    // feeding it a document with an extra or missing key is how a silent
    // zero-coalition run starts.
    const mapped = toEngineIntent('intent-1', flutterDocument());

    expect(Object.keys(mapped).sort()).toEqual(
      [
        'atmosphere',
        'endTime',
        'id',
        'lat',
        'lng',
        'radiusM',
        'startTime',
        'status',
        'userId',
      ].sort(),
    );
  });

  test('the round trip through the real engine forms a coalition', () => {
    // The integration that matters: two documents in storage form, end to
    // end, exactly as two hand-written engine intents would.
    const { formCoalitions } = require('../src/coalitionEngine');

    const intents = [
      toEngineIntent('a', flutterDocument({ idPengguna: 'uid-a' })),
      toEngineIntent('b', flutterDocument({ idPengguna: 'uid-b' })),
    ];

    const { coalitions, unmatched } = formCoalitions(intents);

    expect(unmatched).toEqual([]);
    expect(coalitions).toHaveLength(1);
    expect(coalitions[0].size).toBe(2);
  });
});

describe('suasana translation', () => {
  test.each([
    ['hening', 'quiet'],
    ['diskusi', 'discussion'],
    ['bebas', 'any'],
  ])('%s -> %s', (suasana, atmosphere) => {
    expect(toEngineIntent('x', flutterDocument({ suasana })).atmosphere).toBe(
      atmosphere,
    );
  });

  test('the two direction tables agree', () => {
    for (const [suasana, atmosphere] of Object.entries(
      ATMOSPHERE_BY_SUASANA,
    )) {
      expect(SUASANA_BY_ATMOSPHERE[atmosphere]).toBe(suasana);
    }
  });

  test('the English values from the old schema are NOT accepted', () => {
    // A pre-migration client writing 'quiet' must fail loudly here rather
    // than be mapped to something plausible.
    for (const stale of ['quiet', 'discussion', 'any']) {
      expect(toEngineIntent('x', flutterDocument({ suasana: stale }))).toBeNull();
    }
  });
});

describe('unmappable documents return null', () => {
  test.each([
    ['missing suasana', { suasana: undefined }],
    ['unknown suasana', { suasana: 'karaoke' }],
    ['missing idPengguna', { idPengguna: undefined }],
    ['non-string idPengguna', { idPengguna: 42 }],
    ['missing waktuMulai', { waktuMulai: undefined }],
    ['string waktuMulai', { waktuMulai: '2026-08-11T18:00' }],
    ['missing coordinates', { lat: undefined }],
    ['missing radiusM', { radiusM: undefined }],
  ])('%s', (_label, overrides) => {
    expect(toEngineIntent('x', flutterDocument(overrides))).toBeNull();
  });

  test('null and non-object input', () => {
    expect(toEngineIntent('x', null)).toBeNull();
    expect(toEngineIntent('x', undefined)).toBeNull();
    expect(toEngineIntent('x', 'nope')).toBeNull();
  });
});

describe('status vocabulary', () => {
  test('matches the lifecycle in firestore.rules and proposal F.7', () => {
    expect(STATUS).toEqual({
      ACTIVE: 'aktif',
      MATCHED: 'tercocokkan',
      EXPIRED: 'kedaluwarsa',
      CANCELLED: 'dibatalkan',
    });
  });

  test('the engine always receives active, whatever was stored', () => {
    // Callers pre-filter on status === 'aktif', so this is a constant rather
    // than a translation — asserted so it cannot drift into a stale copy.
    const mapped = toEngineIntent('x', flutterDocument({ status: 'aktif' }));
    expect(mapped.status).toBe('active');
  });
});
