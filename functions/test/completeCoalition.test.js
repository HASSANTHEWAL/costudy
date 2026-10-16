'use strict';

const { completeCoalitionIfReady } = require('../src/completeCoalition');

/**
 * Fake Firestore covering exactly the surface completeCoalitionIfReady uses:
 * one document get, one two-clause query, one update.
 *
 * Records the resulting write rather than the calls made, so an assertion
 * fails if the function writes the wrong VALUE — not merely if it forgets to
 * call update().
 */
function createFakeDb({ coalitions = {}, members = {} } = {}) {
  const updates = [];

  return {
    updates,
    collection(name) {
      return {
        doc(id) {
          return {
            id,
            async get() {
              const data = coalitions[id];
              return { exists: data !== undefined, id, data: () => data };
            },
            async update(patch) {
              updates.push({ collection: name, id, patch });
              Object.assign(coalitions[id], patch);
            },
          };
        },
        where(field, _op, value) {
          const filters = [[field, value]];
          const chain = {
            where(nextField, _nextOp, nextValue) {
              filters.push([nextField, nextValue]);
              return chain;
            },
            async get() {
              const matching = Object.values(members).filter((member) =>
                filters.every(([f, v]) => member[f] === v),
              );
              return { size: matching.length, docs: matching };
            },
          };
          return chain;
        },
      };
    },
  };
}

const ID = 'coalition-1';

function coalition(overrides = {}) {
  return {
    waktuTerbentuk: Date.now(),
    lokasiFinal: { lat: -7.6875, lng: 110.4139 },
    waktuMulai: Date.UTC(2026, 7, 15, 19),
    waktuSelesai: Date.UTC(2026, 7, 15, 21),
    ambangMinimum: 2,
    jumlahAnggota: 3,
    status: 'aktif',
    ...overrides,
  };
}

function member(idPengguna, statusKonfirmasi = 'menunggu') {
  return {
    idKoalisi: ID,
    idPengguna,
    statusKonfirmasi,
    statusKehadiran: 'belum',
  };
}

describe('below the threshold', () => {
  test('one confirmation of two required writes nothing', async () => {
    const db = createFakeDb({
      coalitions: { [ID]: coalition() },
      members: {
        a: member('uid-a', 'hadir'),
        b: member('uid-b'),
        c: member('uid-c'),
      },
    });

    const result = await completeCoalitionIfReady(db, ID);

    expect(result).toMatchObject({ updated: false, confirmed: 1, threshold: 2 });
    expect(db.updates).toHaveLength(0);
  });

  test('no confirmations at all writes nothing', async () => {
    const db = createFakeDb({
      coalitions: { [ID]: coalition() },
      members: { a: member('uid-a'), b: member('uid-b') },
    });

    await completeCoalitionIfReady(db, ID);

    expect(db.updates).toHaveLength(0);
  });
});

describe('at or above the threshold', () => {
  test('the coalition is marked tuntas', async () => {
    const db = createFakeDb({
      coalitions: { [ID]: coalition() },
      members: {
        a: member('uid-a', 'hadir'),
        b: member('uid-b', 'hadir'),
        c: member('uid-c'),
      },
    });

    const result = await completeCoalitionIfReady(db, ID);

    expect(result).toMatchObject({ updated: true, confirmed: 2, threshold: 2 });
    expect(db.updates).toHaveLength(1);
    expect(db.updates[0].collection).toBe('coalitions');
    expect(db.updates[0].id).toBe(ID);
    expect(db.updates[0].patch.status).toBe('tuntas');
    expect(typeof db.updates[0].patch.waktuTuntas).toBe('number');
  });

  test("uses the coalition's OWN ambangMinimum, not a constant", async () => {
    // The assurance contract promised the session on the threshold it was
    // formed under, so that same number decides whether it happened.
    const db = createFakeDb({
      coalitions: { [ID]: coalition({ ambangMinimum: 3 }) },
      members: {
        a: member('uid-a', 'hadir'),
        b: member('uid-b', 'hadir'),
        c: member('uid-c'),
      },
    });

    const result = await completeCoalitionIfReady(db, ID);

    expect(result).toMatchObject({ updated: false, confirmed: 2, threshold: 3 });
    expect(db.updates).toHaveLength(0);
  });

  test('confirmations from another coalition do not count', async () => {
    const db = createFakeDb({
      coalitions: { [ID]: coalition() },
      members: {
        a: member('uid-a', 'hadir'),
        elsewhere: {
          idKoalisi: 'coalition-2',
          idPengguna: 'uid-x',
          statusKonfirmasi: 'hadir',
          statusKehadiran: 'belum',
        },
      },
    });

    const result = await completeCoalitionIfReady(db, ID);

    expect(result.confirmed).toBe(1);
    expect(db.updates).toHaveLength(0);
  });
});

describe('idempotence and bad input', () => {
  test('an already tuntas coalition is not rewritten', async () => {
    // Firestore triggers are at-least-once; a duplicate delivery must be a
    // no-op rather than a second write.
    const db = createFakeDb({
      coalitions: { [ID]: coalition({ status: 'tuntas' }) },
      members: {
        a: member('uid-a', 'hadir'),
        b: member('uid-b', 'hadir'),
      },
    });

    const result = await completeCoalitionIfReady(db, ID);

    expect(result.updated).toBe(false);
    expect(db.updates).toHaveLength(0);
  });

  test('a failed coalition is left alone', async () => {
    const db = createFakeDb({
      coalitions: { [ID]: coalition({ status: 'gagal' }) },
      members: {
        a: member('uid-a', 'hadir'),
        b: member('uid-b', 'hadir'),
      },
    });

    await completeCoalitionIfReady(db, ID);

    expect(db.updates).toHaveLength(0);
  });

  test('a missing coalition is reported, not thrown on', async () => {
    const db = createFakeDb({ coalitions: {}, members: {} });

    const result = await completeCoalitionIfReady(db, 'nope');

    expect(result).toMatchObject({ updated: false, reason: 'missing' });
  });

  test('an absent id is handled', async () => {
    const db = createFakeDb();

    expect(await completeCoalitionIfReady(db, undefined)).toMatchObject({
      updated: false,
      reason: 'no-id',
    });
    expect(await completeCoalitionIfReady(db, '')).toMatchObject({
      updated: false,
      reason: 'no-id',
    });
  });
});
