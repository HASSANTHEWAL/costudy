'use strict';

/**
 * End-to-end run of the whole server chain against the Firestore EMULATOR.
 *
 * Everything below talks to a real Firestore through the real Admin SDK:
 * real queries, real batched writes, real auto-generated document ids, real
 * snapshot semantics. The unit suites use hand-rolled fakes, which is fast and
 * precise but proves only that the code is consistent with my idea of
 * Firestore. This file is what catches the difference — an `exists` that is a
 * property here and a method there, a query that needs a filter the fake
 * ignored, a batch that silently did nothing.
 *
 * FCM is still faked. There is no emulator for it, and sending real pushes
 * from a test suite would be both impossible and rude. The seam is narrow and
 * explicit: `sendEachForMulticast` is recorded, not sent.
 *
 * Run with:  npm run test:e2e --prefix functions
 */

const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const { matchAndNotify } = require('../../src/matchAndNotify');
const { completeCoalitionIfReady } = require('../../src/completeCoalition');

const PROJECT_ID = 'demo-costudy-e2e';

let app;
let db;

/** Records multicasts instead of sending them. */
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

const LIBRARY = { lat: -7.6875, lng: 110.4139 };

function at(hour, minute = 0) {
  return Date.UTC(2026, 7, 15, hour, minute);
}

function intent(idPengguna, overrides = {}) {
  return {
    idPengguna,
    waktuMulai: at(19),
    waktuSelesai: at(21),
    lat: LIBRARY.lat,
    lng: LIBRARY.lng,
    radiusM: 1000,
    suasana: 'hening',
    status: 'aktif',
    ...overrides,
  };
}

/** Wipe every collection this suite touches, between tests. */
async function clearFirestore() {
  for (const name of ['intents', 'coalitions', 'coalitionMembers', 'users']) {
    const snapshot = await db.collection(name).get();
    if (snapshot.empty) continue;
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      'FIRESTORE_EMULATOR_HOST is unset — run via `npm run test:e2e`, which ' +
        'starts the emulator. Refusing to run against a real project.',
    );
  }
  app = initializeApp({ projectId: PROJECT_ID }, `e2e-${Date.now()}`);
  db = getFirestore(app);
});

afterAll(async () => {
  if (app) await deleteApp(app);
});

beforeEach(clearFirestore);

// ── The happy path, end to end ──────────────────────────────────────────────

describe('intents -> coalition -> notification -> confirmation -> tuntas', () => {
  test('the full chain, against real Firestore', async () => {
    // ── 1. Two students register overlapping, compatible intents ───────────
    await db.collection('users').doc('uid-alice').set({
      emailKampus: 'alice@students.uii.ac.id',
      nama: 'Alice Rahmawati',
      jurusan: 'Teknik Informatika',
      statusVerifikasi: true,
      fcmToken: 'token-alice',
    });
    await db.collection('users').doc('uid-bob').set({
      emailKampus: 'bob@students.uii.ac.id',
      nama: 'Bob Santoso',
      jurusan: 'Hukum',
      statusVerifikasi: true,
      fcmToken: 'token-bob',
    });

    await db.collection('intents').doc('intent-alice').set(intent('uid-alice'));
    await db.collection('intents').doc('intent-bob').set(intent('uid-bob'));

    // ── 2. The scheduled matcher runs ──────────────────────────────────────
    const messaging = createFakeMessaging();
    const summary = await matchAndNotify(db, messaging, { now: at(20) });

    expect(summary.intentsConsidered).toBe(2);
    expect(summary.coalitionsFormed).toBe(1);
    expect(summary.unmappable).toEqual([]);

    // ── 3. A coalition document exists, with the agreed schema ─────────────
    const coalitions = await db.collection('coalitions').get();
    expect(coalitions.size).toBe(1);

    const coalitionDoc = coalitions.docs[0];
    const coalition = coalitionDoc.data();
    expect(coalition.status).toBe('aktif');
    expect(coalition.jumlahAnggota).toBe(2);
    expect(coalition.ambangMinimum).toBe(2);
    expect(coalition.waktuMulai).toBe(at(19));
    expect(coalition.waktuSelesai).toBe(at(21));
    expect(coalition.lokasiFinal.lat).toBeCloseTo(LIBRARY.lat, 6);
    // Faculties denormalised server-side; the client never reads other
    // students' profiles.
    expect(coalition.jurusanAnggota.sort()).toEqual(['Hukum', 'Teknik']);

    // ── 4. Member documents use the id shape firestore.rules relies on ─────
    const members = await db.collection('coalitionMembers').get();
    expect(members.size).toBe(2);
    expect(members.docs.map((d) => d.id).sort()).toEqual(
      [`${coalitionDoc.id}_uid-alice`, `${coalitionDoc.id}_uid-bob`].sort(),
    );
    for (const doc of members.docs) {
      expect(doc.data().idKoalisi).toBe(coalitionDoc.id);
      expect(doc.data().statusKonfirmasi).toBe('menunggu');
    }

    // ── 5. Both intents were advanced, so the next run cannot rematch them ─
    const intents = await db.collection('intents').get();
    for (const doc of intents.docs) {
      expect(doc.data().status).toBe('tercocokkan');
    }

    // ── 6. One multicast, to both members, simultaneously ─────────────────
    expect(messaging.calls).toHaveLength(1);
    expect(messaging.calls[0].tokens.sort()).toEqual([
      'token-alice',
      'token-bob',
    ]);
    expect(messaging.calls[0].data).toEqual({
      type: 'session_found',
      coalitionId: coalitionDoc.id,
    });

    // ── 7. First confirmation: below threshold, nothing completes ─────────
    await db
      .collection('coalitionMembers')
      .doc(`${coalitionDoc.id}_uid-alice`)
      .update({ statusKonfirmasi: 'hadir' });

    const firstCheck = await completeCoalitionIfReady(db, coalitionDoc.id);
    expect(firstCheck).toMatchObject({
      updated: false,
      confirmed: 1,
      threshold: 2,
    });
    expect((await coalitionDoc.ref.get()).data().status).toBe('aktif');

    // ── 8. Second confirmation crosses the threshold ──────────────────────
    await db
      .collection('coalitionMembers')
      .doc(`${coalitionDoc.id}_uid-bob`)
      .update({ statusKonfirmasi: 'hadir' });

    const secondCheck = await completeCoalitionIfReady(db, coalitionDoc.id);
    expect(secondCheck).toMatchObject({
      updated: true,
      confirmed: 2,
      threshold: 2,
    });

    const completed = (await coalitionDoc.ref.get()).data();
    expect(completed.status).toBe('tuntas');
    expect(typeof completed.waktuTuntas).toBe('number');

    // ── 9. A duplicate trigger delivery is a no-op ────────────────────────
    const replay = await completeCoalitionIfReady(db, coalitionDoc.id);
    expect(replay.updated).toBe(false);
    expect((await coalitionDoc.ref.get()).data().waktuTuntas).toBe(
      completed.waktuTuntas,
    );
  });
});

// ── Silent expiry, end to end ───────────────────────────────────────────────

describe('an unmatched intent expires in silence', () => {
  test('past its window it becomes kedaluwarsa, with no notification', async () => {
    await db.collection('users').doc('uid-solo').set({
      emailKampus: 'solo@students.uii.ac.id',
      jurusan: 'Psikologi',
      fcmToken: 'token-solo',
    });
    await db.collection('intents').doc('intent-solo').set(intent('uid-solo'));

    const messaging = createFakeMessaging();
    // Clock past the end of the window.
    const summary = await matchAndNotify(db, messaging, { now: at(22) });

    expect(summary.coalitionsFormed).toBe(0);
    expect(summary.intentsExpired).toBe(1);

    const doc = await db.collection('intents').doc('intent-solo').get();
    expect(doc.data().status).toBe('kedaluwarsa');

    // The requirement: the student is never told they were passed over.
    expect(messaging.calls).toHaveLength(0);
    expect((await db.collection('coalitions').get()).empty).toBe(true);
  });

  test('while its window is open it stays aktif for the next run', async () => {
    await db.collection('intents').doc('intent-solo').set(intent('uid-solo'));

    const messaging = createFakeMessaging();
    const summary = await matchAndNotify(db, messaging, { now: at(20) });

    expect(summary.intentsExpired).toBe(0);
    const doc = await db.collection('intents').doc('intent-solo').get();
    expect(doc.data().status).toBe('aktif');
    expect(messaging.calls).toHaveLength(0);
  });
});

// ── Repeated runs ───────────────────────────────────────────────────────────

describe('the scheduler runs every five minutes', () => {
  test('a second run does not rematch students already in a coalition', async () => {
    for (const uid of ['uid-a', 'uid-b']) {
      await db.collection('users').doc(uid).set({ fcmToken: `token-${uid}` });
      await db.collection('intents').doc(`intent-${uid}`).set(intent(uid));
    }

    const first = createFakeMessaging();
    await matchAndNotify(db, first, { now: at(20) });
    expect((await db.collection('coalitions').get()).size).toBe(1);

    // Five minutes later, nothing new has been registered.
    const second = createFakeMessaging();
    const summary = await matchAndNotify(db, second, { now: at(20, 5) });

    // The intents are 'tercocokkan' now, so the query returns nothing and no
    // second coalition is created for the same two students.
    expect(summary.intentsConsidered).toBe(0);
    expect(summary.coalitionsFormed).toBe(0);
    expect((await db.collection('coalitions').get()).size).toBe(1);
    expect(second.calls).toHaveLength(0);
  });

  test('a third student joining later forms a second coalition', async () => {
    for (const uid of ['uid-a', 'uid-b']) {
      await db.collection('users').doc(uid).set({ fcmToken: `token-${uid}` });
      await db.collection('intents').doc(`intent-${uid}`).set(intent(uid));
    }
    await matchAndNotify(db, createFakeMessaging(), { now: at(20) });

    for (const uid of ['uid-c', 'uid-d']) {
      await db.collection('users').doc(uid).set({ fcmToken: `token-${uid}` });
      await db.collection('intents').doc(`intent-${uid}`).set(intent(uid));
    }
    const messaging = createFakeMessaging();
    await matchAndNotify(db, messaging, { now: at(20, 5) });

    expect((await db.collection('coalitions').get()).size).toBe(2);
    expect(messaging.calls).toHaveLength(1);
    expect(messaging.calls[0].tokens.sort()).toEqual([
      'token-uid-c',
      'token-uid-d',
    ]);
  });
});

// ── Notification robustness ─────────────────────────────────────────────────

describe('a member with no FCM token', () => {
  test('still gets a session; only the reachable member is messaged', async () => {
    await db.collection('users').doc('uid-a').set({
      jurusan: 'Ekonomi',
      fcmToken: 'token-a',
    });
    // uid-b never granted notification permission.
    await db.collection('users').doc('uid-b').set({ jurusan: 'Farmasi' });

    await db.collection('intents').doc('intent-a').set(intent('uid-a'));
    await db.collection('intents').doc('intent-b').set(intent('uid-b'));

    const messaging = createFakeMessaging();
    await matchAndNotify(db, messaging, { now: at(20) });

    expect((await db.collection('coalitions').get()).size).toBe(1);
    expect((await db.collection('coalitionMembers').get()).size).toBe(2);
    expect(messaging.calls).toHaveLength(1);
    expect(messaging.calls[0].tokens).toEqual(['token-a']);
  });
});
