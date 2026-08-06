import assert from "node:assert/strict";
import { test } from "node:test";

import { observedCompression, sessionFromTransfers } from "../dist/observed.js";
import { NettingImbalanceError, assertBalanced } from "../dist/netting.js";
import type { Address, Hex32, TransferLog } from "../dist/types.js";

const SECURITY = "0x1111111111111111111111111111111111111111111111111111111111111111" as Hex32;
const CASH = "0x2222222222222222222222222222222222222222" as Address;

const deskA = "0x000000000000000000000000000000000000000a" as Address;
const deskB = "0x000000000000000000000000000000000000000b" as Address;
const deskC = "0x000000000000000000000000000000000000000c" as Address;
const ZERO = "0x0000000000000000000000000000000000000000" as Address;

const move = (from: Address, to: Address, value: bigint): TransferLog => ({ from, to, value });

test("a round trip between two desks nets away entirely", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [
    move(deskA, deskB, 100n),
    move(deskB, deskA, 100n),
  ]);

  assert.equal(observed.session.legs.length, 0, "nobody has to move");
  assert.equal(observed.flatParties, 2);
  assert.equal(observed.counted, 2);
});

test("a chain of hops collapses to its endpoints", () => {
  // A pays B, B pays C. Only A and C actually change position.
  const observed = sessionFromTransfers(SECURITY, CASH, [
    move(deskA, deskB, 500n),
    move(deskB, deskC, 500n),
  ]);

  assert.deepEqual(
    observed.session.legs.map((leg) => [leg.party, leg.quantityDelta]),
    [
      [deskA, -500n],
      [deskC, 500n],
    ],
  );
  assert.equal(observed.flatParties, 1, "the desk in the middle is left flat");
});

test("the cash leg is left at zero because a transfer log does not carry a price", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [move(deskA, deskB, 7n)]);

  for (const leg of observed.session.legs) {
    assert.equal(leg.cashDelta, 0n);
  }
});

test("issues and redeems are dropped rather than breaking the balance", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [
    move(ZERO, deskA, 1_000n),
    move(deskA, deskB, 400n),
    move(deskB, ZERO, 50n),
  ]);

  assert.equal(observed.skipped, 2);
  assert.equal(observed.counted, 1);
  assert.deepEqual(
    observed.session.legs.map((leg) => leg.quantityDelta),
    [-400n, 400n],
  );
});

test("a self transfer moves nothing and does not become a leg", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [move(deskA, deskA, 900n)]);

  assert.equal(observed.skipped, 1);
  assert.equal(observed.session.legs.length, 0);
});

test("legs come out sorted, so the same window always produces the same session", () => {
  const forwards = sessionFromTransfers(SECURITY, CASH, [
    move(deskC, deskA, 10n),
    move(deskA, deskB, 4n),
  ]);
  const backwards = sessionFromTransfers(SECURITY, CASH, [
    move(deskA, deskB, 4n),
    move(deskC, deskA, 10n),
  ]);

  assert.deepEqual(forwards.session, backwards.session);
});

test("whatever the selection, party to party transfers always net to zero", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [
    move(deskA, deskB, 13n),
    move(deskB, deskC, 5n),
    move(deskC, deskA, 2n),
  ]);

  const residual = observed.session.legs.reduce((sum, leg) => sum + leg.quantityDelta, 0n);
  assert.equal(residual, 0n);
});

test("a negative value is rejected rather than silently reversed", () => {
  assert.throws(
    () => sessionFromTransfers(SECURITY, CASH, [move(deskA, deskB, -1n)]),
    RangeError,
  );
});

test("compression is measured against transfers, not against doubled trades", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [
    move(deskA, deskB, 100n),
    move(deskB, deskA, 100n),
    move(deskA, deskC, 30n),
  ]);

  const report = observedCompression(observed);

  assert.equal(report.observedTransfers, 3);
  assert.equal(report.netTransfers, 2, "only A and C still have to move");
  assert.equal(report.removed, 1);
  assert.equal(report.flatParties, 1);
  assert.ok(report.ratio > 0.33 && report.ratio < 0.34);
});

test("an empty window reports nothing rather than dividing by zero", () => {
  const report = observedCompression(sessionFromTransfers(SECURITY, CASH, []));

  assert.equal(report.observedTransfers, 0);
  assert.equal(report.ratio, 0);
});

test("a derived session satisfies the same balance rule the engine enforces", () => {
  const observed = sessionFromTransfers(SECURITY, CASH, [
    move(deskA, deskB, 1n),
    move(deskB, deskC, 1n),
  ]);

  assert.doesNotThrow(() => assertBalanced(observed.session.legs));

  // And the check is real: nudge one leg and it fails the way the engine would.
  const tampered = observed.session.legs.map((leg, index) =>
    index === 0 ? { ...leg, quantityDelta: leg.quantityDelta + 1n } : leg,
  );
  assert.throws(() => assertBalanced(tampered), NettingImbalanceError);
});
