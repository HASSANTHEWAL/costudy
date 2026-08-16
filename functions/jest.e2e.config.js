'use strict';

/**
 * Jest config for the end-to-end suite, which needs a running Firestore
 * emulator. Separate from the default run for the same reason as the rules
 * config: `npm test` must stay fast and dependency-free.
 */
module.exports = {
  rootDir: __dirname,
  testMatch: ['<rootDir>/test/e2e/**/*.e2e.test.js'],
  testPathIgnorePatterns: ['/node_modules/'],
  // Real Firestore over gRPC, plus a cold emulator on the first test.
  testTimeout: 30000,
};
