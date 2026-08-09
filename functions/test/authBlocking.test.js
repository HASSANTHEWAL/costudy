'use strict';

const {
  handleBeforeUserCreated,
  handleBeforeUserSignedIn,
  CampusAuthError,
} = require('../src/authBlocking');

const { REASONS } = require('../src/emailDomain');

/** A blocking event as Firebase Authentication delivers it. */
function event(data) {
  return { data };
}

describe('handleBeforeUserCreated', () => {
  it('admits a student and records the canonical identity', () => {
    const result = handleBeforeUserCreated(
      event({ uid: 'abc123', email: 'nada@students.uii.ac.id', emailVerified: false }),
    );

    expect(result.customClaims.campus).toBe('uii');
    expect(result.customClaims.canonicalEmail).toBe('nada@students.uii.ac.id');
  });

  it('never asserts email ownership it has not observed', () => {
    // Setting emailVerified here would hand a working account to anyone who
    // typed a classmate's address. Firebase sets it on a successful link
    // sign-in; this handler must not pre-empt that.
    const result = handleBeforeUserCreated(
      event({ uid: 'abc123', email: 'nada@students.uii.ac.id', emailVerified: false }),
    );

    expect(result).not.toHaveProperty('emailVerified');
    expect(result.customClaims).not.toHaveProperty('campusVerified');
  });

  it.each([
    ['a consumer address', 'nada@gmail.com'],
    ['the staff domain', 'dosen@uii.ac.id'],
    ['another university', 'budi@students.ugm.ac.id'],
    ['a lookalike domain', 'nada@students.uii.ac.id.evil.com'],
  ])('blocks account creation for %s', (_label, email) => {
    expect(() => handleBeforeUserCreated(event({ uid: 'x', email }))).toThrow(CampusAuthError);
  });

  it('blocks an event with no email at all', () => {
    expect(() => handleBeforeUserCreated(event({ uid: 'x' }))).toThrow(CampusAuthError);
    expect(() => handleBeforeUserCreated(event(undefined))).toThrow(CampusAuthError);
    expect(() => handleBeforeUserCreated(undefined)).toThrow(CampusAuthError);
  });

  it('carries the reason code and the student-facing message', () => {
    // index.js maps this onto HttpsError('invalid-argument', message); the
    // message is what the student actually reads on the sign-in screen.
    expect.assertions(2);
    try {
      handleBeforeUserCreated(event({ uid: 'x', email: 'dosen@uii.ac.id' }));
    } catch (error) {
      expect(error.reason).toBe(REASONS.UII_NON_STUDENT);
      expect(error.message).toContain('students.uii.ac.id');
    }
  });
});

describe('handleBeforeUserSignedIn', () => {
  it('grants campusVerified only once the address is actually verified', () => {
    const verified = handleBeforeUserSignedIn(
      event({ email: 'nada@students.uii.ac.id', emailVerified: true }),
    );
    expect(verified.sessionClaims.campusVerified).toBe(true);

    const unverified = handleBeforeUserSignedIn(
      event({ email: 'nada@students.uii.ac.id', emailVerified: false }),
    );
    expect(unverified.sessionClaims.campusVerified).toBe(false);
  });

  it('treats a missing emailVerified flag as not verified', () => {
    const result = handleBeforeUserSignedIn(event({ email: 'nada@students.uii.ac.id' }));

    expect(result.sessionClaims.campusVerified).toBe(false);
  });

  it('is not fooled by a truthy non-boolean emailVerified', () => {
    const result = handleBeforeUserSignedIn(
      event({ email: 'nada@students.uii.ac.id', emailVerified: 'yes' }),
    );

    expect(result.sessionClaims.campusVerified).toBe(false);
  });

  it('re-checks the domain, catching accounts that predate a tightened rule', () => {
    expect(() =>
      handleBeforeUserSignedIn(event({ email: 'legacy@uii.ac.id', emailVerified: true })),
    ).toThrow(CampusAuthError);
  });

  it('carries the canonical identity into the session', () => {
    const result = handleBeforeUserSignedIn(
      event({ email: 'Nada@Students.UII.ac.id', emailVerified: true }),
    );

    expect(result.sessionClaims.canonicalEmail).toBe('nada@students.uii.ac.id');
    expect(result.sessionClaims.campus).toBe('uii');
  });
});
