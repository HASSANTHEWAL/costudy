'use strict';

/**
 * FR-03 — availability windows are invisible to other users.
 *
 * These tests run against the Firestore emulator with real security rules
 * loaded. They are the proof that intent privacy is enforced by the database
 * rather than merely respected by the app: a hostile client talking straight
 * to Firestore is exactly what the rules have to stop.
 *
 * Run with:  npm run test:rules --prefix functions
 * (the script starts the emulator; running plain `jest` will skip this file)
 *
 * NOTE ON POSITIVE CONTROLS. A suite made only of "this is denied" assertions
 * passes just as happily against rules that deny everything, which would be a
 * broken app and a green test run. Every denial below is therefore paired
 * with the corresponding permitted case.
 */

const fs = require('node:fs');
const path = require('node:path');

const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const {
  doc,
  getDoc,
  setDoc,
  deleteDoc,
  updateDoc,
  collection,
  collectionGroup,
  query,
  where,
  getDocs,
  Timestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-costudy-rules';

const ALICE = 'uid-alice';
const BOB = 'uid-bob';

/** A verified student token, as Firebase Auth would issue after link sign-in. */
function student(email) {
  return { email, email_verified: true };
}

const ALICE_AUTH = student('alice@students.uii.ac.id');
const BOB_AUTH = student('bob@students.uii.ac.id');

/** Epoch ms — the unit the matcher's overlap arithmetic expects. */
const MULAI = Date.UTC(2026, 7, 11, 18, 0);
const SELESAI = Date.UTC(2026, 7, 11, 21, 0);

function intentFor(idPengguna, overrides = {}) {
  return {
    idPengguna,
    waktuMulai: MULAI,
    waktuSelesai: SELESAI,
    lat: -7.6875,
    lng: 110.4139,
    radiusM: 1000,
    suasana: 'hening',
    status: 'aktif',
    dibuatPada: Timestamp.now(),
    ...overrides,
  };
}

const COALITION_ID = 'coalition-1';

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, '../../firestore.rules'),
        'utf8',
      ),
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  // Seed with rules disabled — this is the world the matcher's Admin SDK
  // would have created. Alice is in a coalition; Bob is not.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'intents/alice-intent'), intentFor(ALICE));
    await setDoc(doc(db, 'intents/alice-intent-2'), intentFor(ALICE));
    await setDoc(doc(db, 'intents/bob-intent'), intentFor(BOB));

    await setDoc(doc(db, 'users/uid-alice'), {
      emailKampus: 'alice@students.uii.ac.id',
      statusVerifikasi: true,
      fcmToken: 'token-alice',
    });
    await setDoc(doc(db, 'users/uid-bob'), {
      emailKampus: 'bob@students.uii.ac.id',
      statusVerifikasi: true,
      fcmToken: 'token-bob',
    });

    await setDoc(doc(db, `coalitions/${COALITION_ID}`), {
      waktuTerbentuk: Date.now(),
      lokasiFinal: { lat: -7.6875, lng: 110.4139 },
      waktuMulai: MULAI,
      waktuSelesai: SELESAI,
      ambangMinimum: 2,
      jumlahAnggota: 2,
      status: 'aktif',
    });
    // Deterministic id — the coalitions rule proves membership with exists()
    // on exactly this path.
    await setDoc(doc(db, `coalitionMembers/${COALITION_ID}_${ALICE}`), {
      idKoalisi: COALITION_ID,
      idPengguna: ALICE,
      statusKonfirmasi: 'menunggu',
      statusKehadiran: 'belum',
    });
  });
});

function aliceDb() {
  return testEnv.authenticatedContext(ALICE, ALICE_AUTH).firestore();
}

function bobDb() {
  return testEnv.authenticatedContext(BOB, BOB_AUTH).firestore();
}

// ── The requirement ─────────────────────────────────────────────────────────

describe("FR-03: one student cannot reach another's intents", () => {
  test("Bob CANNOT read Alice's intent document", async () => {
    await assertFails(getDoc(doc(bobDb(), 'intents/alice-intent')));
  });

  test("Bob CANNOT list Alice's intents, even filtering by her id", async () => {
    const q = query(
      collection(bobDb(), 'intents'),
      where('idPengguna', '==', ALICE),
    );
    await assertFails(getDocs(q));
  });

  test('Bob CANNOT list the intents collection unfiltered', async () => {
    // The query cannot prove every result would be Bob's, so it is rejected
    // outright — he cannot even learn how many intents exist.
    await assertFails(getDocs(collection(bobDb(), 'intents')));
  });

  test('Bob CANNOT reach intents through a collection-group query', async () => {
    await assertFails(getDocs(query(collectionGroup(bobDb(), 'intents'))));
  });

  test("Bob CANNOT write to, or delete, Alice's intent", async () => {
    await assertFails(
      updateDoc(doc(bobDb(), 'intents/alice-intent'), { status: 'dibatalkan' }),
    );
    await assertFails(deleteDoc(doc(bobDb(), 'intents/alice-intent')));
  });

  // Positive controls — without these the suite would pass on deny-all rules.
  test('Alice CAN read her own intent', async () => {
    await assertSucceeds(getDoc(doc(aliceDb(), 'intents/alice-intent')));
  });

  test('Alice CAN list her own intents', async () => {
    const q = query(
      collection(aliceDb(), 'intents'),
      where('idPengguna', '==', ALICE),
    );
    const snapshot = await assertSucceeds(getDocs(q));
    expect(snapshot.size).toBe(2);
  });

  test('Alice CANNOT list her own intents without the ownership filter', async () => {
    await assertFails(getDocs(collection(aliceDb(), 'intents')));
  });
});

// ── Ownership on write ──────────────────────────────────────────────────────

describe('FR-02: a student may only create intents for themselves', () => {
  test('Alice CAN create an intent with her own id', async () => {
    await assertSucceeds(
      setDoc(doc(aliceDb(), 'intents/new-alice'), intentFor(ALICE)),
    );
  });

  test("Alice CANNOT create an intent carrying Bob's id", async () => {
    await assertFails(setDoc(doc(aliceDb(), 'intents/forged'), intentFor(BOB)));
  });

  test('Alice CAN cancel her own intent', async () => {
    await assertSucceeds(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), {
        status: 'dibatalkan',
      }),
    );
  });

  test('Alice CANNOT promote her own intent to tercocokkan', async () => {
    // Only the matcher, via the Admin SDK, may advance status.
    await assertFails(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), {
        status: 'tercocokkan',
      }),
    );
  });

  test('Alice CANNOT expire her own intent', async () => {
    await assertFails(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), {
        status: 'kedaluwarsa',
      }),
    );
  });

  test('Alice CANNOT rewrite the time or place of an existing intent', async () => {
    await assertFails(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), {
        status: 'dibatalkan',
        waktuMulai: MULAI + 3600000,
      }),
    );
  });

  test('Alice CAN delete her own intent', async () => {
    await assertSucceeds(deleteDoc(doc(aliceDb(), 'intents/alice-intent')));
  });
});

// ── Who counts as a student ─────────────────────────────────────────────────

describe('FR-01 / NFR-03: only verified campus accounts may write', () => {
  test('an unauthenticated client CANNOT read or write intents', async () => {
    const db = testEnv.unauthenticatedContext().firestore();

    await assertFails(getDoc(doc(db, 'intents/alice-intent')));
    await assertFails(setDoc(doc(db, 'intents/anon'), intentFor('anyone')));
  });

  test('a signed-in but UNVERIFIED campus account CANNOT create an intent', async () => {
    const db = testEnv
      .authenticatedContext('uid-unverified', {
        email: 'nada@students.uii.ac.id',
        email_verified: false,
      })
      .firestore();

    await assertFails(
      setDoc(doc(db, 'intents/unverified'), intentFor('uid-unverified')),
    );
  });

  test('a verified NON-campus account CANNOT create an intent', async () => {
    const db = testEnv
      .authenticatedContext('uid-outsider', student('someone@gmail.com'))
      .firestore();

    await assertFails(
      setDoc(doc(db, 'intents/outsider'), intentFor('uid-outsider')),
    );
  });

  test('a lookalike domain CANNOT create an intent', async () => {
    const db = testEnv
      .authenticatedContext(
        'uid-lookalike',
        student('nada@students.uii.ac.id.evil.com'),
      )
      .firestore();

    await assertFails(
      setDoc(doc(db, 'intents/lookalike'), intentFor('uid-lookalike')),
    );
  });

  test('the UII staff domain CANNOT create an intent', async () => {
    const db = testEnv
      .authenticatedContext('uid-staff', student('dosen@uii.ac.id'))
      .firestore();

    await assertFails(setDoc(doc(db, 'intents/staff'), intentFor('uid-staff')));
  });
});

// ── Document shape ──────────────────────────────────────────────────────────

describe('intent documents are validated on write', () => {
  test('rejects an end time at or before the start time', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/backwards'),
        intentFor(ALICE, { waktuSelesai: MULAI }),
      ),
    );
  });

  test('rejects an unknown suasana', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/bad-suasana'),
        intentFor(ALICE, { suasana: 'karaoke' }),
      ),
    );
  });

  test('rejects an English suasana left over from the old schema', async () => {
    // Guards the migration specifically: a stale client writing 'quiet'
    // should fail loudly rather than store a value the mapper cannot read.
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/english'),
        intentFor(ALICE, { suasana: 'quiet' }),
      ),
    );
  });

  test('rejects a status other than aktif on create', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/prematched'),
        intentFor(ALICE, { status: 'tercocokkan' }),
      ),
    );
  });

  test('rejects an out-of-range radius', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/huge'),
        intentFor(ALICE, { radiusM: 50000 }),
      ),
    );
    await assertFails(
      setDoc(doc(aliceDb(), 'intents/zero'), intentFor(ALICE, { radiusM: 0 })),
    );
  });

  test('rejects coordinates outside the globe', async () => {
    await assertFails(
      setDoc(doc(aliceDb(), 'intents/nowhere'), intentFor(ALICE, { lat: 91 })),
    );
  });

  test('rejects smuggled extra fields', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/extra'),
        intentFor(ALICE, { isAdmin: true }),
      ),
    );
  });

  test('rejects a missing required field', async () => {
    const incomplete = intentFor(ALICE);
    delete incomplete.suasana;

    await assertFails(setDoc(doc(aliceDb(), 'intents/incomplete'), incomplete));
  });
});

// ── users ───────────────────────────────────────────────────────────────────

describe('users: the FCM token record is strictly the owner\'s', () => {
  test('Alice CAN read and write her own record', async () => {
    await assertSucceeds(getDoc(doc(aliceDb(), 'users/uid-alice')));
    await assertSucceeds(
      setDoc(
        doc(aliceDb(), 'users/uid-alice'),
        { fcmToken: 'new-token', statusVerifikasi: true },
        { merge: true },
      ),
    );
  });

  test("Bob CANNOT read Alice's record", async () => {
    // Her FCM token is there, and so is the fact that she uses the app at all.
    await assertFails(getDoc(doc(bobDb(), 'users/uid-alice')));
  });

  test("Bob CANNOT overwrite Alice's FCM token", async () => {
    // Otherwise he could redirect her session notifications to his device.
    await assertFails(
      setDoc(
        doc(bobDb(), 'users/uid-alice'),
        { fcmToken: 'bob-device' },
        { merge: true },
      ),
    );
  });

  test('nobody can list the users collection', async () => {
    // There is no directory. Enumerating students is exactly the browsing
    // affordance the product removes.
    await assertFails(getDocs(collection(aliceDb(), 'users')));
  });

  test('an unverified account CANNOT write its own record', async () => {
    const db = testEnv
      .authenticatedContext('uid-unverified', {
        email: 'nada@students.uii.ac.id',
        email_verified: false,
      })
      .firestore();

    await assertFails(
      setDoc(doc(db, 'users/uid-unverified'), { fcmToken: 'x' }),
    );
  });

  test('clearing the token on sign-out is allowed', async () => {
    await assertSucceeds(
      setDoc(
        doc(aliceDb(), 'users/uid-alice'),
        { fcmToken: null },
        { merge: true },
      ),
    );
  });

  test('Profile Setup can write nama and jurusan', async () => {
    await assertSucceeds(
      setDoc(
        doc(aliceDb(), 'users/uid-alice'),
        { nama: 'Alice Rahmawati', jurusan: 'Teknik Informatika' },
        { merge: true },
      ),
    );
  });

  test('rejects an over-long nama', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'users/uid-alice'),
        { nama: 'x'.repeat(81) },
        { merge: true },
      ),
    );
  });

  test('rejects an unknown preferensiSuasana', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'users/uid-alice'),
        { preferensiSuasana: 'karaoke' },
        { merge: true },
      ),
    );
  });

  test('rejects smuggled extra fields', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'users/uid-alice'),
        { peran: 'admin' },
        { merge: true },
      ),
    );
  });
});

// ── coalitions and membership ───────────────────────────────────────────────

describe('coalitions are readable only by their members', () => {
  test('Alice, a member, CAN read her coalition', async () => {
    await assertSucceeds(getDoc(doc(aliceDb(), `coalitions/${COALITION_ID}`)));
  });

  test('Bob, not a member, CANNOT read it', async () => {
    await assertFails(getDoc(doc(bobDb(), `coalitions/${COALITION_ID}`)));
  });

  test('nobody can list coalitions', async () => {
    // No screen browses sessions, and a query would reveal how many exist.
    await assertFails(getDocs(collection(aliceDb(), 'coalitions')));
  });

  test('no client can write a coalition', async () => {
    // Only the matcher, via the Admin SDK. A client-written coalition would
    // be a session nobody agreed to.
    await assertFails(
      setDoc(doc(aliceDb(), 'coalitions/forged'), {
        waktuTerbentuk: Date.now(),
        lokasiFinal: { lat: 0, lng: 0 },
        waktuMulai: MULAI,
        waktuSelesai: SELESAI,
        ambangMinimum: 2,
        jumlahAnggota: 2,
        status: 'aktif',
      }),
    );
    await assertFails(
      updateDoc(doc(aliceDb(), `coalitions/${COALITION_ID}`), {
        status: 'gagal',
      }),
    );
  });

  test('Alice CAN read her own membership record', async () => {
    await assertSucceeds(
      getDoc(doc(aliceDb(), `coalitionMembers/${COALITION_ID}_${ALICE}`)),
    );
  });

  test("Bob CANNOT read Alice's membership record", async () => {
    await assertFails(
      getDoc(doc(bobDb(), `coalitionMembers/${COALITION_ID}_${ALICE}`)),
    );
  });

  test('Bob CANNOT enumerate a coalition roster', async () => {
    // Filtering by coalition rather than by himself: the rule requires the
    // query to prove every result is his, so this is refused.
    await assertFails(
      getDocs(
        query(
          collection(bobDb(), 'coalitionMembers'),
          where('idKoalisi', '==', COALITION_ID),
        ),
      ),
    );
  });

  test('Alice CAN list her own memberships', async () => {
    const snapshot = await assertSucceeds(
      getDocs(
        query(
          collection(aliceDb(), 'coalitionMembers'),
          where('idPengguna', '==', ALICE),
        ),
      ),
    );
    expect(snapshot.size).toBe(1);
  });

  test('no client can create a membership record', async () => {
    await assertFails(
      setDoc(doc(aliceDb(), `coalitionMembers/${COALITION_ID}_${BOB}`), {
        idKoalisi: COALITION_ID,
        idPengguna: BOB,
        statusKonfirmasi: 'menunggu',
        statusKehadiran: 'belum',
      }),
    );
  });
});

// ── FR-07: attendance confirmation ──────────────────────────────────────────

describe('a student confirms their own attendance, and nothing else', () => {
  const aliceMember = `coalitionMembers/${COALITION_ID}_${ALICE}`;

  test('Alice CAN mark herself hadir', async () => {
    await assertSucceeds(
      updateDoc(doc(aliceDb(), aliceMember), { statusKonfirmasi: 'hadir' }),
    );
  });

  test("Bob CANNOT confirm on Alice's behalf", async () => {
    await assertFails(
      updateDoc(doc(bobDb(), aliceMember), { statusKonfirmasi: 'hadir' }),
    );
  });

  test('Alice CANNOT set an arbitrary statusKonfirmasi', async () => {
    await assertFails(
      updateDoc(doc(aliceDb(), aliceMember), { statusKonfirmasi: 'juara' }),
    );
  });

  test('Alice CANNOT self-report statusKehadiran', async () => {
    // Whether she actually turned up is the system's judgement, not a
    // self-report — otherwise the completion metric measures nothing.
    await assertFails(
      updateDoc(doc(aliceDb(), aliceMember), {
        statusKonfirmasi: 'hadir',
        statusKehadiran: 'hadir',
      }),
    );
  });

  test('Alice CANNOT move her membership to another coalition', async () => {
    await assertFails(
      updateDoc(doc(aliceDb(), aliceMember), {
        statusKonfirmasi: 'hadir',
        idKoalisi: 'coalition-somewhere-else',
      }),
    );
  });

  test('Alice CANNOT reassign her membership to Bob', async () => {
    await assertFails(
      updateDoc(doc(aliceDb(), aliceMember), {
        statusKonfirmasi: 'hadir',
        idPengguna: BOB,
      }),
    );
  });

  test('an unverified account CANNOT confirm', async () => {
    const db = testEnv
      .authenticatedContext(ALICE, {
        email: 'alice@students.uii.ac.id',
        email_verified: false,
      })
      .firestore();

    await assertFails(
      updateDoc(doc(db, aliceMember), { statusKonfirmasi: 'hadir' }),
    );
  });
});

// ── Nothing else is reachable ───────────────────────────────────────────────

describe('no other collection is open', () => {
  test('a student cannot read or write arbitrary collections', async () => {
    const db = aliceDb();

    await assertFails(getDoc(doc(db, 'admin/config')));
    await assertFails(setDoc(doc(db, 'admin/config'), { x: 1 }));
    await assertFails(getDocs(collection(db, 'sessions')));
  });
});
