import assert from "node:assert/strict";
import { test } from "node:test";

import {
  NettingImbalanceError,
  assertBalanced,
  compressionOf,
  netTrades,
  withoutFlatLegs,
} from "../dist/netting.js";
import type { Address, Hex32, Trade } from "../dist/types.js";

const SECURITY = "0x1111111111111111111111111111111111111111111111111111111111111111" as Hex32;
const CASH = "0x2222222222222222222222222222222222222222" as Address;

const deskA = "0x000000000000000000000000000000000000000a" as Address;
const deskB = "0x000000000000000000000000000000000000000b" as Address;
const deskC = "0x000000000000000000000000000000000000000c" as Address;

test("netTrades collapses offsetting trades into one net position", () => {
  const trades: Trade[] = [
    { seller: deskA, buyer: deskB, quantity: 400n, consideration: 82_000n },
    { seller: deskB, buyer: deskA, quantity: 380n, consideration: 78_000n },
  ];

  const session = netTrades(SECURITY, CASH, trades);
  const byParty = new Map(session.legs.map((leg) => [leg.party, leg]));

  assert.equal(byParty.get(deskA)?.quantityDelta, -20n);
  assert.equal(byParty.get(deskB)?.quantityDelta, 20n);
  assert.equal(byParty.get(deskA)?.cashDelta, 4_000n);
  assert.equal(byParty.get(deskB)?.cashDelta, -4_000n);
});

test("netTrades always produces a session that nets to zero", () => {
  const trades: Trade[] = [
    { seller: deskA, buyer: deskB, quantity: 600n, consideration: 120_000n },
    { seller: deskB, buyer: deskC, quantity: 250n, consideration: 51_000n },
    { seller: deskC, buyer: deskA, quantity: 100n, consideration: 20_500n },
  ];

  const session = netTrades(SECURITY, CASH, trades);

  const quantity = session.legs.reduce((sum, leg) => sum + leg.quantityDelta, 0n);
  const cash = session.legs.reduce((sum, leg) => sum + leg.cashDelta, 0n);

  assert.equal(quantity, 0n);
  assert.equal(cash, 0n);
});

test("netTrades is deterministic regardless of trade order", () => {
  const trades: Trade[] = [
    { seller: deskA, buyer: deskB, quantity: 400n, consideration: 82_000n },
    { seller: deskC, buyer: deskA, quantity: 150n, consideration: 30_000n },
  ];

  const forward = netTrades(SECURITY, CASH, trades);
  const reversed = netTrades(SECURITY, CASH, [...trades].reverse());

  assert.deepEqual(forward.legs, reversed.legs);
});

test("netTrades rejects a self trade", () => {
  assert.throws(
    () => netTrades(SECURITY, CASH, [{ seller: deskA, buyer: deskA, quantity: 1n, consideration: 1n }]),
    RangeError,
  );
});

test("netTrades rejects non-positive amounts", () => {
  assert.throws(
    () => netTrades(SECURITY, CASH, [{ seller: deskA, buyer: deskB, quantity: 0n, consideration: 1n }]),
    RangeError,
  );
  assert.throws(
    () => netTrades(SECURITY, CASH, [{ seller: deskA, buyer: deskB, quantity: 1n, consideration: 0n }]),
    RangeError,
  );
});

test("assertBalanced surfaces the residual it found", () => {
  try {
    assertBalanced([{ party: deskA, quantityDelta: 5n, cashDelta: 0n }]);
    assert.fail("expected an imbalance error");
  } catch (error) {
    assert.ok(error instanceof NettingImbalanceError);
    assert.equal(error.quantityResidual, 5n);
    assert.equal(error.cashResidual, 0n);
  }
});

test("compressionOf reports the transfers removed", () => {
  const session = {
    security: SECURITY,
    cash: CASH,
    legs: [
      { party: deskA, quantityDelta: 20n, cashDelta: -4_000n },
      { party: deskB, quantityDelta: -20n, cashDelta: 4_000n },
    ],
  };

  const report = compressionOf(session, 12_000);

  assert.equal(report.grossTransfers, 24_000);
  assert.equal(report.netTransfers, 4);
  assert.ok(report.ratio > 0.999);
});
