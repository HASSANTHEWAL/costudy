'use strict';

const {
  verifyCampusEmail,
  canonicalizeLocalPart,
  REASONS,
} = require('../src/emailDomain');

describe('verifyCampusEmail — accepts', () => {
  it('a plain student address', () => {
    const result = verifyCampusEmail('nada@students.uii.ac.id');

    expect(result.valid).toBe(true);
    expect(result.email).toBe('nada@students.uii.ac.id');
    expect(result.canonicalEmail).toBe('nada@students.uii.ac.id');
    expect(result.localPart).toBe('nada');
    expect(result.domain).toBe('students.uii.ac.id');
  });

  it('an address with surrounding whitespace and mixed case', () => {
    const result = verifyCampusEmail('  Nada.Taufik@Students.UII.ac.id  ');

    expect(result.valid).toBe(true);
    expect(result.email).toBe('nada.taufik@students.uii.ac.id');
  });

  it('a numeric student-number address', () => {
    expect(verifyCampusEmail('25523274@students.uii.ac.id').valid).toBe(true);
  });

  it('dots in the local part, without collapsing them', () => {
    // Gmail would treat this as the same mailbox as nadataufik@. We do not
    // assume that for a domain we do not control.
    const result = verifyCampusEmail('nada.taufik@students.uii.ac.id');

    expect(result.valid).toBe(true);
    expect(result.canonicalEmail).toBe('nada.taufik@students.uii.ac.id');
  });
});

describe('verifyCampusEmail — rejects', () => {
  it.each([
    ['undefined', undefined],
    ['null', null],
    ['an empty string', ''],
    ['whitespace only', '   '],
    ['a number', 25523274],
  ])('%s as missing', (_label, input) => {
    const result = verifyCampusEmail(input);

    expect(result.valid).toBe(false);
    expect(result.reason).toBe(REASONS.MISSING);
    expect(result.message).toBeTruthy();
  });

  it.each([
    ['no @', 'nadastudents.uii.ac.id'],
    ['two @', 'nada@nada@students.uii.ac.id'],
    ['empty local part', '@students.uii.ac.id'],
    ['empty domain', 'nada@'],
    ['internal whitespace', 'na da@students.uii.ac.id'],
    ['leading dot in local part', '.nada@students.uii.ac.id'],
    ['trailing dot in local part', 'nada.@students.uii.ac.id'],
    ['consecutive dots', 'na..da@students.uii.ac.id'],
    ['dotless domain', 'nada@students'],
  ])('%s as malformed', (_label, input) => {
    const result = verifyCampusEmail(input);

    expect(result.valid).toBe(false);
    expect(result.reason).toBe(REASONS.MALFORMED);
  });

  it.each([
    ['the staff domain', 'dosen@uii.ac.id'],
    ['a faculty subdomain', 'admin@fkip.uii.ac.id'],
    // Still a UII address, so the near-miss message is more useful here than
    // a flat "not a campus address".
    ['a subdomain of the student domain', 'nada@fk.students.uii.ac.id'],
  ])('%s with a specific, helpful reason', (_label, input) => {
    const result = verifyCampusEmail(input);

    expect(result.valid).toBe(false);
    expect(result.reason).toBe(REASONS.UII_NON_STUDENT);
    // The near-miss message must name the right domain to use.
    expect(result.message).toContain('students.uii.ac.id');
  });

  it.each([
    ['a consumer address', 'nada@gmail.com'],
    ['another university', 'nada@students.ugm.ac.id'],
    ['a lookalike suffix', 'nada@notuii.ac.id'],
    // The attack the suffix check has to survive: the campus domain appears
    // in the string, but the actual registrable domain is evil.com.
    ['the student domain as a prefix', 'nada@students.uii.ac.id.evil.com'],
  ])('%s as not campus', (_label, input) => {
    const result = verifyCampusEmail(input);

    expect(result.valid).toBe(false);
    expect(result.reason).toBe(REASONS.NOT_CAMPUS);
  });
});

describe('plus-addressing', () => {
  it('is rejected by default, to stop one mailbox minting many accounts', () => {
    const result = verifyCampusEmail('nada+alt@students.uii.ac.id');

    expect(result.valid).toBe(false);
    expect(result.reason).toBe(REASONS.ALIAS_NOT_ALLOWED);
  });

  it('is accepted when explicitly allowed, and canonicalised to one identity', () => {
    const tagged = verifyCampusEmail('nada+skripsi@students.uii.ac.id', {
      allowPlusAddressing: true,
    });
    const plain = verifyCampusEmail('nada@students.uii.ac.id');

    expect(tagged.valid).toBe(true);
    expect(tagged.email).toBe('nada+skripsi@students.uii.ac.id');
    // Different addresses, same person — this is the point of canonicalEmail.
    expect(tagged.canonicalEmail).toBe(plain.canonicalEmail);
  });

  it('canonicalises the local part independently of the domain rules', () => {
    expect(canonicalizeLocalPart('nada+a+b')).toBe('nada');
    expect(canonicalizeLocalPart('nada')).toBe('nada');
    expect(canonicalizeLocalPart('+tagonly')).toBe('');
  });
});

describe('campusDomain override', () => {
  it('supports a different university without code changes', () => {
    const options = { campusDomain: 'students.ugm.ac.id' };

    expect(verifyCampusEmail('budi@students.ugm.ac.id', options).valid).toBe(true);
    expect(verifyCampusEmail('nada@students.uii.ac.id', options).valid).toBe(false);
  });
});
