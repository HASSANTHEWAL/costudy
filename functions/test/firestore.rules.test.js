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

/** Epoch ms — the coalition engine's time format. */
const START = Date.UTC(2026, 7, 11, 18, 0);
const END = Date.UTC(2026, 7, 11, 21, 0);

function intentFor(userId, overrides = {}) {
  return {
    userId,
    startTime: START,
    endTime: END,
    lat: -7.6875,
    lng: 110.4139,
    radiusM: 1000,
    atmosphere: 'quiet',
    status: 'active',
    createdAt: Timestamp.now(),
    ...overrides,
  };
}

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

  // Seed one intent owned by Alice, bypassing rules. This is the document
  // Bob must not be able to reach by any route.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'intents/alice-intent'), intentFor(ALICE));
    await setDoc(doc(db, 'intents/alice-intent-2'), intentFor(ALICE));
    await setDoc(doc(db, 'intents/bob-intent'), intentFor(BOB));
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
  test('Bob CANNOT read Alice\'s intent document', async () => {
    await assertFails(getDoc(doc(bobDb(), 'intents/alice-intent')));
  });

  test("Bob CANNOT list Alice's intents, even filtering by her userId", async () => {
    const q = query(
      collection(bobDb(), 'intents'),
      where('userId', '==', ALICE),
    );
    await assertFails(getDocs(q));
  });

  test('Bob CANNOT list the intents collection unfiltered', async () => {
    // The query cannot prove every result would be Bob's, so it is rejected
    // outright — he cannot even learn how many intents exist.
    await assertFails(getDocs(collection(bobDb(), 'intents')));
  });

  test('Bob CANNOT reach intents through a collection-group query', async () => {
    // No `match /{path=**}/intents/{id}` rule exists, so there is no path
    // variant that opens them up.
    await assertFails(getDocs(query(collectionGroup(bobDb(), 'intents'))));
  });

  test('Bob CANNOT write to, or delete, Alice\'s intent', async () => {
    await assertFails(
      updateDoc(doc(bobDb(), 'intents/alice-intent'), { status: 'cancelled' }),
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
      where('userId', '==', ALICE),
    );
    const snapshot = await assertSucceeds(getDocs(q));
    expect(snapshot.size).toBe(2);
  });

  test('Alice CANNOT list her own intents without the ownership filter', async () => {
    // Same rule, seen from the owner's side: the filter is what makes the
    // query provably safe, so omitting it fails even for your own data.
    await assertFails(getDocs(collection(aliceDb(), 'intents')));
  });
});

// ── Ownership on write ──────────────────────────────────────────────────────

describe('FR-02: a student may only create intents for themselves', () => {
  test('Alice CAN create an intent with her own userId', async () => {
    await assertSucceeds(
      setDoc(doc(aliceDb(), 'intents/new-alice'), intentFor(ALICE)),
    );
  });

  test("Alice CANNOT create an intent carrying Bob's userId", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), 'intents/forged'), intentFor(BOB)),
    );
  });

  test('Alice CAN cancel her own intent', async () => {
    await assertSucceeds(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), {
        status: 'cancelled',
      }),
    );
  });

  test('Alice CANNOT promote her own intent to matched', async () => {
    // Only the coalition engine, via the Admin SDK, may advance status.
    await assertFails(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), { status: 'matched' }),
    );
  });

  test('Alice CANNOT rewrite the time or place of an existing intent', async () => {
    await assertFails(
      updateDoc(doc(aliceDb(), 'intents/alice-intent'), {
        status: 'cancelled',
        startTime: START + 3600000,
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
        intentFor(ALICE, { endTime: START }),
      ),
    );
  });

  test('rejects an unknown atmosphere', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/bad-atmosphere'),
        intentFor(ALICE, { atmosphere: 'karaoke' }),
      ),
    );
  });

  test('rejects a status other than active on create', async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/prematched'),
        intentFor(ALICE, { status: 'matched' }),
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
    // hasOnly() — otherwise a client could attach anything it liked to its
    // own document and later code might trust it.
    await assertFails(
      setDoc(
        doc(aliceDb(), 'intents/extra'),
        intentFor(ALICE, { isAdmin: true }),
      ),
    );
  });

  test('rejects a missing required field', async () => {
    const incomplete = intentFor(ALICE);
    delete incomplete.atmosphere;

    await assertFails(
      setDoc(doc(aliceDb(), 'intents/incomplete'), incomplete),
    );
  });
});

// ── Nothing else is reachable ───────────────────────────────────────────────

describe('no other collection is open', () => {
  test('a student cannot read or write arbitrary collections', async () => {
    const db = aliceDb();

    await assertFails(getDoc(doc(db, 'users/uid-alice')));
    await assertFails(setDoc(doc(db, 'users/uid-alice'), { name: 'Alice' }));
    await assertFails(getDocs(collection(db, 'coalitions')));
    await assertFails(setDoc(doc(db, 'coalitions/x'), { size: 2 }));
  });
});
