/**
 * Sessions derived from what the chain already did.
 *
 * Everything in `netting.ts` starts from trades a venue reports. This module
 * starts one step earlier, from the ERC20 transfer log itself, and answers a
 * different question: of the movements that actually happened, how many needed
 * to. That makes netting measurable against traffic nobody arranged for the
 * demonstration.
 *
 * The cash leg is deliberately absent. A transfer log records that shares moved,
 * not what was paid for them, so inventing a cash delta here would be inventing
 * data. Legs come out with `cashDelta` at zero and the venue supplies the money
 * side when it settles for real.
 */

import { encodeFunctionData } from "viem";

import { nettingEngineAbi } from "./abi.js";
import { assertBalanced } from "./netting.js";
import type { Address, Hex32, Leg, ObservedReport, Session, TransferLog } from "./types.js";

/** The address a token mints from and burns to. */
const ZERO = "0x0000000000000000000000000000000000000000" as Address;

/** A session folded out of transfer logs, with what was left out of it. */
export interface ObservedSession {
  session: Session;
  /** Transfers that fed the session. */
  counted: number;
  /** Issues and redeems, which cannot net between parties and were dropped. */
  skipped: number;
  /** Parties who traded and ended exactly where they started. */
  flatParties: number;
}

/**
 * Folds transfer logs of one security into a session.
 *
 * Mints and burns are dropped rather than rejected. They are ordinary events in
 * a token's life, but a session that includes one does not net to zero between
 * parties, so counting them would make every real window unsettleable.
 *
 * @param security Canonical registry id of the security being netted.
 * @param cash Token the venue will use for the money leg.
 * @param transfers Transfer logs, in any order.
 */
export function sessionFromTransfers(
  security: Hex32,
  cash: Address,
  transfers: readonly TransferLog[],
): ObservedSession {
  const deltas = new Map<Address, bigint>();
  let skipped = 0;

  const bump = (party: Address, delta: bigint): void => {
    deltas.set(party, (deltas.get(party) ?? 0n) + delta);
  };

  for (const transfer of transfers) {
    if (transfer.value < 0n) throw new RangeError("transfer value cannot be negative");

    if (transfer.from === ZERO || transfer.to === ZERO) {
      skipped += 1;
      continue;
    }
    if (transfer.from === transfer.to) {
      // A self transfer moves nothing and would only add a flat party.
      skipped += 1;
      continue;
    }

    bump(transfer.from, -transfer.value);
    bump(transfer.to, transfer.value);
  }

  const parties = [...deltas.keys()].sort((a, b) => (a.toLowerCase() < b.toLowerCase() ? -1 : 1));

  const legs: Leg[] = parties
    .filter((party) => deltas.get(party) !== 0n)
    .map((party) => ({ party, quantityDelta: deltas.get(party) as bigint, cashDelta: 0n }));

  assertBalanced(legs);

  return {
    session: { security, cash, legs },
    counted: transfers.length - skipped,
    skipped,
    flatParties: parties.length - legs.length,
  };
}

/**
 * Measures a derived session against the transfers it replaces.
 *
 * `compressionOf` compares a session with settling trades gross, where each
 * trade costs two transfers. Here the comparison is against transfers that are
 * already on chain, so one observed transfer is one movement and no doubling
 * applies.
 */
export function observedCompression(observed: ObservedSession): ObservedReport {
  const netTransfers = observed.session.legs.length;
  const removed = Math.max(0, observed.counted - netTransfers);
  const ratio = observed.counted === 0 ? 0 : removed / observed.counted;

  return {
    observedTransfers: observed.counted,
    netTransfers,
    removed,
    flatParties: observed.flatParties,
    ratio,
  };
}

/**
 * Encodes a session as the exact call a venue makes to settle it.
 *
 * Handing back calldata rather than a transaction keeps this module free of a
 * signer. Whoever holds the venue key decides what to do with the bytes.
 */
export function settleSessionCalldata(session: Session, grossTrades: number): `0x${string}` {
  return encodeFunctionData({
    abi: nettingEngineAbi,
    functionName: "settleSession",
    args: [
      {
        security: session.security,
        cash: session.cash,
        legs: session.legs.map((leg) => ({
          party: leg.party,
          quantityDelta: leg.quantityDelta,
          cashDelta: leg.cashDelta,
        })),
      },
      BigInt(grossTrades),
    ],
  });
}
