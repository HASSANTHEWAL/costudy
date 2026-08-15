'use strict';

const { matchAndNotify, MIN_THRESHOLD } = require('../src/matchAndNotify');

// ── Fakes ───────────────────────────────────────────────────────────────────
//
// Hand-rolled rather than a mocking library: the Firestore surface used here
// is small (one query, batches, doc gets) and a fake that actually records
// writes lets the tests assert on the RESULTING STATE rather than on which
// methods were called. Asserting call sequences would pass just as happily
// against code that wrote the wrong values.

function createFakeDb({ intents = {}, users = {} } = {}) {
  const writes = { sets: [], updates: [] };
  let autoId = 0;

  const docRef = (collection, id) => ({
    id,
    _collection: collection,
    async get() {
      const store = collection === 'users' ? users : intents;
      const data = store[id];
      return {
        exists: data !== undefined,
        id,
        data: () => data,
      };
    },
  });

  const db = {
    writes,
    collection(name) {
      return {
        doc(id) {
          if (id === undefined) {
            autoId += 1;
            return docRef(name, `${name}-generated-${autoId}`);
          }
          return docRef(name, id);
        },
        where(field, op, value) {
          return {
            async get() {
              const matching = Object.entries(intents).filter(
                ([, data]) => data[field] === value,
              );
              return {
                size: matching.length,
                forEach(callback) {
                  for (const [id, data] of matching) {
                    callback({ id, data: () => data });
                  }
                },
              };
            },
          };
        },
      };
    },
    batch() {
      const staged = { sets: [], updates: [] };
      return {
        set(ref, data) {
          staged.sets.push({ collection: ref._collection, id: ref.id, data });
        },
        update(ref, data) {
          staged.updates.push({
            collection: ref._collection,
            id: ref.id,
            data,
          });
        },
        async commit() {
          writes.sets.push(...staged.sets);
          writes.updates.push(...staged.updates);
          // Reflect status changes back into the store so a later assertion
          // sees the same world the function believes it created.
          for (const update of staged.updates) {
            if (update.collection === 'intents' && intents[update.id]) {
              Object.assign(intents[update.id], update.data);
            }
          }
        },
      };
    },
  };

  return db;
}

function createFakeMessaging() {
  const calls = [];
  return {
    calls,
    async sendEachForMulticast(message) {
      calls.push(message);
      return { successCount: message.tokens.length, failureCount: 0 };
    },
  };
}

// ── Fixtures ────────────────────────────────────────────────────────────────

const LIBRARY = { lat: -7.6875, lng: 110.4139 };

function at(hour, minute = 0) {
  return Date.UTC(2026, 7, 11, hour, minute);
}

function intent(overrides = {}) {
  return {
    idPengguna: 'uid-a',
    waktuMulai: at(18),
    waktuSelesai: at(21),
    lat: LIBRARY.lat,
    lng: LIBRARY.lng,
    radiusM: 1000,
    suasana: 'hening',
    status: 'aktif',
    ...overrides,
  };
}

/** Just after the fixture windows close, so they count as stale. */
const AFTER_WINDOWS = at(22);

// ── Matched path ────────────────────────────────────────────────────────────

describe('a coalition forms', () => {
  let db;
  let messaging;

  beforeEach(async () => {
    db = createFakeDb({
      intents: {
        'intent-a': intent({ idPengguna: 'uid-a' }),
        'intent-b': intent({ idPengguna: 'uid-b' }),
      },
      users: {
        'uid-a': { fcmToken: 'token-a' },
        'uid-b': { fcmToken: 'token-b' },
      },
    });
    messaging = createFakeMessaging();
    await matchAndNotify(db, messaging, { now: at(19) });
  });

  test('both intents are advanced to tercocokkan', () => {
    const statuses = db.writes.updates
      .filter((u) => u.collection === 'intents')
      .map((u) => u.data.status);

    expect(statuses).toHaveLength(2);
    expect(statuses.every((s) => s === 'tercocokkan')).toBe(true);
  });

  test('one coalition document is written, with the agreed schema', () => {
    const coalitions = db.writes.sets.filter(
      (s) => s.collection === 'coalitions',
    );

    expect(coalitions).toHaveLength(1);
    const doc = coalitions[0].data;
    expect(doc.status).toBe('aktif');
    expect(doc.jumlahAnggota).toBe(2);
    expect(doc.ambangMinimum).toBe(MIN_THRESHOLD);
    expect(doc.lokasiFinal.lat).toBeCloseTo(LIBRARY.lat, 6);
    expect(doc.lokasiFinal.lng).toBeCloseTo(LIBRARY.lng, 6);
    // The common window, not either member's own.
    expect(doc.waktuMulai).toBe(at(18));
    expect(doc.waktuSelesai).toBe(at(21));
    expect(typeof doc.waktuTerbentuk).toBe('number');
  });

  test('one member document per student, keyed for the rules lookup', () => {
    const members = db.writes.sets.filter(
      (s) => s.collection === 'coalitionMembers',
    );
    const coalitionId = db.writes.sets.find(
      (s) => s.collection === 'coalitions',
    ).id;

    expect(members).toHaveLength(2);
    expect(members.map((m) => m.data.idPengguna).sort()).toEqual([
      'uid-a',
      'uid-b',
    ]);
    // firestore.rules proves membership with exists() on this exact id.
    expect(members.map((m) => m.id).sort()).toEqual(
      [`${coalitionId}_uid-a`, `${coalitionId}_uid-b`].sort(),
    );
    for (const member of members) {
      expect(member.data.idKoalisi).toBe(coalitionId);
      expect(member.data.statusKonfirmasi).toBe('menunggu');
    }
  });

  test('every member is notified in a single simultaneous multicast', () => {
    // One call, not two. Nobody is asked to accept anybody — the session is
    // announced to everyone at the same moment.
    expect(messaging.calls).toHaveLength(1);

    const message = messaging.calls[0];
    expect(message.tokens.sort()).toEqual(['token-a', 'token-b']);
    expect(message.notification.title).toBe('Sesi Ditemukan! 🎯');
    expect(message.data.type).toBe('session_found');
    expect(message.data.coalitionId).toBe(
      db.writes.sets.find((s) => s.collection === 'coalitions').id,
    );
  });
});

// ── The assurance contract ──────────────────────────────────────────────────

describe('below the minimum threshold', () => {
  test('a lone intent produces no coalition and no notification', async () => {
    const db = createFakeDb({
      intents: { 'intent-a': intent({ idPengguna: 'uid-a' }) },
      users: { 'uid-a': { fcmToken: 'token-a' } },
    });
    const messaging = createFakeMessaging();

    await matchAndNotify(db, messaging, { now: at(19) });

    expect(db.writes.sets).toHaveLength(0);
    expect(messaging.calls).toHaveLength(0);
  });

  test('incompatible intents form nothing, and are not told so', async () => {
    // Two students, mutually exclusive atmospheres. Each is alone in practice.
    const db = createFakeDb({
      intents: {
        'intent-a': intent({ idPengguna: 'uid-a', suasana: 'hening' }),
        'intent-b': intent({ idPengguna: 'uid-b', suasana: 'diskusi' }),
      },
      users: {
        'uid-a': { fcmToken: 'token-a' },
        'uid-b': { fcmToken: 'token-b' },
      },
    });
    const messaging = createFakeMessaging();

    await matchAndNotify(db, messaging, { now: at(19) });

    expect(
      db.writes.sets.filter((s) => s.collection === 'coalitions'),
    ).toHaveLength(0);
    expect(messaging.calls).toHaveLength(0);
  });
});

// ── Silent expiry ───────────────────────────────────────────────────────────

describe('unmatched intents expire silently', () => {
  test('a closed window becomes kedaluwarsa with NO notification', async () => {
    const db = createFakeDb({
      intents: { 'intent-a': intent({ idPengguna: 'uid-a' }) },
      users: { 'uid-a': { fcmToken: 'token-a' } },
    });
    const messaging = createFakeMessaging();

    const summary = await matchAndNotify(db, messaging, { now: AFTER_WINDOWS });

    expect(summary.intentsExpired).toBe(1);
    expect(db.writes.updates).toEqual([
      {
        collection: 'intents',
        id: 'intent-a',
        data: { status: 'kedaluwarsa' },
      },
    ]);

    // The hard requirement: failure is never announced. A student is not told
    // they were passed over, because being passed over is the experience this
    // product exists to remove.
    expect(messaging.calls).toHaveLength(0);
  });

  test('a window still open is left aktif for the next run', async () => {
    const db = createFakeDb({
      intents: { 'intent-a': intent({ idPengguna: 'uid-a' }) },
      users: {},
    });
    const messaging = createFakeMessaging();

    const summary = await matchAndNotify(db, messaging, { now: at(19) });

    expect(summary.intentsExpired).toBe(0);
    expect(db.writes.updates).toHaveLength(0);
    expect(messaging.calls).toHaveLength(0);
  });
});

// ── Notification robustness ─────────────────────────────────────────────────

describe('members without an FCM token', () => {
  test('are skipped without failing the coalition', async () => {
    const db = createFakeDb({
      intents: {
        'intent-a': intent({ idPengguna: 'uid-a' }),
        'intent-b': intent({ idPengguna: 'uid-b' }),
      },
      // uid-b has a user record but never granted notification permission.
      users: {
        'uid-a': { fcmToken: 'token-a' },
        'uid-b': { fcmToken: null },
      },
    });
    const messaging = createFakeMessaging();

    await matchAndNotify(db, messaging, { now: at(19) });

    // The coalition still exists for both of them.
    expect(
      db.writes.sets.filter((s) => s.collection === 'coalitions'),
    ).toHaveLength(1);
    expect(
      db.writes.sets.filter((s) => s.collection === 'coalitionMembers'),
    ).toHaveLength(2);

    // Only the reachable member is messaged.
    expect(messaging.calls).toHaveLength(1);
    expect(messaging.calls[0].tokens).toEqual(['token-a']);
  });

  test('no messaging call at all when nobody is reachable', async () => {
    const db = createFakeDb({
      intents: {
        'intent-a': intent({ idPengguna: 'uid-a' }),
        'intent-b': intent({ idPengguna: 'uid-b' }),
      },
      users: {},
    });
    const messaging = createFakeMessaging();

    await matchAndNotify(db, messaging, { now: at(19) });

    expect(
      db.writes.sets.filter((s) => s.collection === 'coalitions'),
    ).toHaveLength(1);
    expect(messaging.calls).toHaveLength(0);
  });
});

// ── Schema handling ─────────────────────────────────────────────────────────

describe('input handling', () => {
  test('an unmappable document is reported, not silently expired', async () => {
    const db = createFakeDb({
      intents: {
        'intent-bad': intent({ suasana: 'karaoke' }),
        'intent-a': intent({ idPengguna: 'uid-a' }),
        'intent-b': intent({ idPengguna: 'uid-b' }),
      },
      users: {
        'uid-a': { fcmToken: 'token-a' },
        'uid-b': { fcmToken: 'token-b' },
      },
    });
    const messaging = createFakeMessaging();

    const summary = await matchAndNotify(db, messaging, { now: at(19) });

    // A schema fault is a bug to fix, not a student who failed to match — so
    // it is surfaced and the document is left alone rather than expired.
    expect(summary.unmappable).toEqual(['intent-bad']);
    expect(
      db.writes.updates.find((u) => u.id === 'intent-bad'),
    ).toBeUndefined();
    expect(summary.coalitionsFormed).toBe(1);
  });

  test('only aktif intents are considered', async () => {
    const db = createFakeDb({
      intents: {
        'intent-a': intent({ idPengguna: 'uid-a' }),
        'intent-done': intent({ idPengguna: 'uid-b', status: 'tercocokkan' }),
        'intent-gone': intent({ idPengguna: 'uid-c', status: 'dibatalkan' }),
      },
      users: { 'uid-a': { fcmToken: 'token-a' } },
    });
    const messaging = createFakeMessaging();

    const summary = await matchAndNotify(db, messaging, { now: at(19) });

    // Only one intent was in play, so nothing can form.
    expect(summary.intentsConsidered).toBe(1);
    expect(summary.coalitionsFormed).toBe(0);
  });

  test('an empty collection is a no-op', async () => {
    const db = createFakeDb();
    const messaging = createFakeMessaging();

    const summary = await matchAndNotify(db, messaging, { now: at(19) });

    expect(summary).toMatchObject({
      intentsConsidered: 0,
      coalitionsFormed: 0,
      intentsExpired: 0,
    });
    expect(db.writes.sets).toHaveLength(0);
    expect(messaging.calls).toHaveLength(0);
  });
});
