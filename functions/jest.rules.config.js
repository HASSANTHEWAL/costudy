'use strict';

/**
 * Jest config for the Firestore security rules suite.
 *
 * A separate config rather than CLI flags on the default run. The obvious
 * one-liner —
 *
 *   jest --testPathIgnorePatterns=/node_modules/ test/firestore.rules.test.js
 *
 * — silently does the wrong thing: testPathIgnorePatterns is an array option,
 * so Jest absorbs the trailing path as a second ignore pattern. The rules file
 * gets skipped, the rest of the suite runs, and the command exits 0 looking
 * like a pass.
 */
module.exports = {
  rootDir: __dirname,
  testMatch: ['<rootDir>/test/firestore.rules.test.js'],
  testPathIgnorePatterns: ['/node_modules/'],
  // The emulator is remote-ish; the default 5s can be tight on a cold JVM.
  testTimeout: 20000,
};
