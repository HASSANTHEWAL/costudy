'use strict';

/**
 * CoStudy — Coalition Formation Engine benchmark
 *
 * Measures NFR-02: coalition formation completes in under 3 seconds for 500
 * active intents.
 *
 * Kept out of the Jest suite deliberately. Wall-clock assertions are the
 * classic source of CI flakes, and a correctness suite that fails because a
 * shared runner was busy teaches the team to ignore red. Run with:
 *
 *     npm run bench --prefix functions
 *
 * Exits non-zero if the NFR is breached, so it can still gate a release
 * later without being able to break the everyday test run.
 *
 * ── WHY THREE CASES ─────────────────────────────────────────────────────────
 * Placement is greedy first-fit: each intent is offered to every open group
 * until one accepts. Cost is therefore O(k * g), where g is the number of
 * groups open at that moment — and g depends on the DATA, not on k.
 *
 *   clustered    — intents are mutually compatible, so groups fill to
 *                  capacity and g stays near k/maxCapacity. The first group
 *                  offered usually accepts, so placement is close to O(k).
 *                  This is the pilot scenario from proposal D.5: one
 *                  location, one time window, one population.
 *
 *   scattered    — city-wide spread. Looks adversarial, isn't: density stays
 *                  high enough that groups keep forming. Kept as a caution
 *                  against assuming scatter implies fragmentation.
 *
 *   pathological — a lattice engineered so no pair can ever group. g reaches
 *                  k, giving the true O(k²) upper bound, with every rejection
 *                  paying for the centroid + haversine check first.
 *
 * Reporting only the clustered case would flatter the engine; reporting only
 * a random scatter would misidentify where the worst case actually lives.
 */

const { formCoalitions } = require('../src/coalitionEngine');

const INTENT_COUNT = 500;
const NFR_02_BUDGET_MS = 3000;
const RUNS = 7;

const LIBRARY = { lat: -7.6875, lng: 110.4139 };
const METRES_PER_DEGREE_LAT = 110574;
const METRES_PER_DEGREE_LNG = 111320 * Math.cos((LIBRARY.lat * Math.PI) / 180);

/**
 * mulberry32 — small seeded PRNG.
 *
 * Seeded so the benchmark is reproducible. An unseeded generator would make
 * every run a slightly different workload, which defeats the purpose of
 * quoting a number in the proposal.
 */
function makeRng(seed) {
  let state = seed >>> 0;
  return function next() {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function offsetMetres(origin, northM, eastM) {
  return {
    lat: origin.lat + northM / METRES_PER_DEGREE_LAT,
    lng: origin.lng + eastM / METRES_PER_DEGREE_LNG,
  };
}

/** Epoch ms for a wall-clock time on the pilot evening. */
function at(hour, minute = 0) {
  return Date.UTC(2026, 7, 10, hour, minute);
}

function pick(rng, values) {
  return values[Math.floor(rng() * values.length)];
}

/**
 * CLUSTERED — the pilot scenario. Everyone within 300 m of the library,
 * everyone free across the same evening, generous travel radii, atmosphere
 * mostly unconstrained. Groups should fill to capacity.
 */
function generateClustered(count) {
  const rng = makeRng(0x0c057d1);
  const intents = [];

  for (let i = 0; i < count; i += 1) {
    // Uniform over a 300 m disc around the library.
    const angle = rng() * 2 * Math.PI;
    const distance = 300 * Math.sqrt(rng());
    const point = offsetMetres(LIBRARY, distance * Math.cos(angle), distance * Math.sin(angle));

    // 18:00-21:00 with up to 20 minutes of jitter each end. Worst-case pair
    // still overlaps by well over the 60-minute minimum.
    const startJitter = Math.floor(rng() * 41) - 20;
    const endJitter = Math.floor(rng() * 41) - 20;

    intents.push({
      id: `clustered-${i}`,
      userId: `user-${i}`,
      startTime: at(18, startJitter),
      endTime: at(21, endJitter),
      ...point,
      radiusM: pick(rng, [1000, 1500, 2000]),
      // Weighted toward 'any' so atmosphere rarely fragments a group.
      atmosphere: rng() < 0.8 ? 'any' : pick(rng, ['quiet', 'discussion']),
      status: 'active',
    });
  }

  return intents;
}

/**
 * SCATTERED — city-wide spread, a plausible pre-density failure mode.
 *
 * 500 intents over a ~15 km box with a 500 m travel radius. Intuition says
 * this should fragment badly; it does not. At that spread the density is
 * still ~2.2 intents/km², so each intent has roughly seven reachable
 * neighbours and groups keep forming. Included precisely because it looks
 * adversarial and is not — random scatter cannot be relied on to produce the
 * singleton case, which is what the lattice below is for.
 */
function generateScattered(count) {
  const rng = makeRng(0xbadf00d);
  const intents = [];
  const SPREAD_M = 15000;

  for (let i = 0; i < count; i += 1) {
    const point = offsetMetres(
      LIBRARY,
      (rng() - 0.5) * SPREAD_M,
      (rng() - 0.5) * SPREAD_M,
    );

    intents.push({
      id: `scattered-${i}`,
      userId: `user-${i}`,
      startTime: at(18),
      endTime: at(21),
      ...point,
      radiusM: 500,
      atmosphere: i % 2 === 0 ? 'quiet' : 'discussion',
      status: 'active',
    });
  }

  return intents;
}

/**
 * PATHOLOGICAL — the guaranteed O(k²) upper bound. Synthetic, not a user
 * distribution; it exists to bound the algorithm, not to model a campus.
 *
 * Intents sit on a regular 2 km lattice with a 300 m travel radius. Any two
 * members are >= 2 km apart, so the centroid lands >= 1 km from each — always
 * outside the 300 m radius. No pair can ever group, so every intent opens its
 * own group and g reaches k. A lattice guarantees this; random placement only
 * hopes for it.
 *
 * The other fields are chosen so the CHEAP constraints all pass:
 *
 *   - one shared time window, so the pairwise overlap check succeeds
 *   - atmosphere 'any' throughout, so the atmosphere check succeeds
 *   - distinct users, so the same-user check succeeds
 *
 * Every rejection therefore falls through to the centroid + haversine work,
 * the most expensive constraint in the engine. This is the worst input the
 * greedy baseline can be handed at this size: k² placement attempts, each
 * paying full price before failing.
 */
function generatePathological(count) {
  const intents = [];
  const SPACING_M = 2000;
  const side = Math.ceil(Math.sqrt(count));

  for (let i = 0; i < count; i += 1) {
    const row = Math.floor(i / side);
    const column = i % side;
    const point = offsetMetres(LIBRARY, row * SPACING_M, column * SPACING_M);

    intents.push({
      id: `lattice-${i}`,
      userId: `user-${i}`,
      startTime: at(18),
      endTime: at(21),
      ...point,
      radiusM: 300,
      atmosphere: 'any',
      status: 'active',
    });
  }

  return intents;
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function benchmark(label, intents) {
  // One warm-up pass so JIT compilation is not charged to the first timed run.
  formCoalitions(intents);

  const timings = [];
  let result;
  for (let run = 0; run < RUNS; run += 1) {
    const started = performance.now();
    result = formCoalitions(intents);
    timings.push(performance.now() - started);
  }

  return {
    label,
    intents: intents.length,
    medianMs: median(timings),
    minMs: Math.min(...timings),
    maxMs: Math.max(...timings),
    coalitions: result.coalitions.length,
    matched: intents.length - result.unmatched.length,
    unmatched: result.unmatched.length,
  };
}

function format(value, decimals = 2) {
  return value.toFixed(decimals);
}

function report(results) {
  console.log('CoStudy coalition engine — NFR-02 benchmark');
  console.log(`Node ${process.version} · ${INTENT_COUNT} active intents · median of ${RUNS} runs\n`);

  const header = ['case', 'median', 'min', 'max', 'coalitions', 'matched', 'unmatched'];
  const rows = results.map((r) => [
    r.label,
    `${format(r.medianMs)} ms`,
    `${format(r.minMs)} ms`,
    `${format(r.maxMs)} ms`,
    String(r.coalitions),
    String(r.matched),
    String(r.unmatched),
  ]);

  const widths = header.map((_, column) =>
    Math.max(header[column].length, ...rows.map((row) => row[column].length)),
  );
  const line = (cells) => cells.map((cell, i) => cell.padEnd(widths[i])).join('  ');

  console.log(line(header));
  console.log(widths.map((w) => '-'.repeat(w)).join('  '));
  for (const row of rows) console.log(line(row));

  console.log(`\nNFR-02 budget: ${NFR_02_BUDGET_MS} ms for ${INTENT_COUNT} intents`);

  let breached = false;
  for (const r of results) {
    const headroom = NFR_02_BUDGET_MS / r.medianMs;
    const verdict = r.medianMs < NFR_02_BUDGET_MS ? 'PASS' : 'FAIL';
    if (verdict === 'FAIL') breached = true;
    console.log(`  ${verdict}  ${r.label} — ${format(r.medianMs)} ms (${format(headroom, 0)}x headroom)`);
  }

  return breached;
}

function main() {
  const results = [
    benchmark('clustered', generateClustered(INTENT_COUNT)),
    benchmark('scattered', generateScattered(INTENT_COUNT)),
    benchmark('pathological', generatePathological(INTENT_COUNT)),
  ];

  const breached = report(results);
  process.exitCode = breached ? 1 : 0;
}

main();
