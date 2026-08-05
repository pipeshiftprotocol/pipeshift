/**
 * Multilateral netting.
 *
 * Venues match trades gross. Settling them gross means two transfers per trade,
 * which is the wrong unit of work: a desk that buys 400 shares and sells 380 in
 * the same session only owes 20. This module collapses a list of trades into one
 * net position per party, which is what actually has to move.
 */

import type { Address, CompressionReport, Hex32, Leg, Session, Trade } from "./types.js";

/** Thrown when a computed session would create or destroy value. */
export class NettingImbalanceError extends Error {
  readonly quantityResidual: bigint;
  readonly cashResidual: bigint;

  constructor(quantityResidual: bigint, cashResidual: bigint) {
    super(
      `session does not net to zero: quantity residual ${quantityResidual}, cash residual ${cashResidual}`,
    );
    this.name = "NettingImbalanceError";
    this.quantityResidual = quantityResidual;
    this.cashResidual = cashResidual;
  }
}

/**
 * Collapses trades in one security into a net position per party.
 *
 * Legs are sorted by party address so the same trade set always produces the
 * same session, which keeps sessions reproducible across venues.
 */
export function netTrades(security: Hex32, cash: Address, trades: readonly Trade[]): Session {
  const quantity = new Map<Address, bigint>();
  const cashFlow = new Map<Address, bigint>();

  const bump = (map: Map<Address, bigint>, party: Address, delta: bigint): void => {
    map.set(party, (map.get(party) ?? 0n) + delta);
  };

  for (const trade of trades) {
    if (trade.quantity <= 0n) throw new RangeError("trade quantity must be positive");
    if (trade.consideration <= 0n) throw new RangeError("trade consideration must be positive");
    if (trade.seller === trade.buyer) throw new RangeError(`self trade for ${trade.seller}`);

    bump(quantity, trade.seller, -trade.quantity);
    bump(quantity, trade.buyer, trade.quantity);
    bump(cashFlow, trade.seller, trade.consideration);
    bump(cashFlow, trade.buyer, -trade.consideration);
  }

  const parties = new Set<Address>([...quantity.keys(), ...cashFlow.keys()]);

  const legs: Leg[] = [...parties]
    .map((party) => ({
      party,
      quantityDelta: quantity.get(party) ?? 0n,
      cashDelta: cashFlow.get(party) ?? 0n,
    }))
    .sort((a, b) => (a.party.toLowerCase() < b.party.toLowerCase() ? -1 : 1));

  assertBalanced(legs);

  return { security, cash, legs };
}

/**
 * Verifies that a session nets to zero on both legs.
 *
 * The engine rejects an unbalanced session on chain, but catching it here turns
 * a reverted transaction into a local error with the residual attached.
 */
export function assertBalanced(legs: readonly Leg[]): void {
  let quantityResidual = 0n;
  let cashResidual = 0n;

  for (const leg of legs) {
    quantityResidual += leg.quantityDelta;
    cashResidual += leg.cashDelta;
  }

  if (quantityResidual !== 0n || cashResidual !== 0n) {
    throw new NettingImbalanceError(quantityResidual, cashResidual);
  }
}

/** Reports how many transfers a session removes against settling gross. */
export function compressionOf(session: Session, grossTrades: number): CompressionReport {
  const grossTransfers = grossTrades * 2;

  let netTransfers = 0;
  let flatParties = 0;

  for (const leg of session.legs) {
    const moves = (leg.quantityDelta !== 0n ? 1 : 0) + (leg.cashDelta !== 0n ? 1 : 0);
    netTransfers += moves;
    if (moves === 0) flatParties += 1;
  }

  const ratio = grossTransfers === 0 ? 0 : 1 - netTransfers / grossTransfers;

  return { grossTransfers, netTransfers, flatParties, ratio };
}

/** Drops parties whose net position is flat on both legs. */
export function withoutFlatLegs(session: Session): Session {
  return {
    ...session,
    legs: session.legs.filter((leg) => leg.quantityDelta !== 0n || leg.cashDelta !== 0n),
  };
}

/** Thrown when sessions that cannot be combined are handed to the aggregator. */
export class IncompatibleSessionsError extends Error {
  constructor(reason: string) {
    super(`sessions cannot be aggregated: ${reason}`);
    this.name = "IncompatibleSessionsError";
  }
}

/**
 * Combines the sessions of several venues into one.
 *
 * Netting per venue leaves value on the table. A desk that ends long on one venue
 * and short the same name on another still moves both positions in full, even though
 * the two cancel. Aggregating first means only the difference moves.
 *
 * Sessions must cover the same security and the same cash token, because netting
 * across instruments would need a price and pricing is not a settlement concern.
 */
export function aggregateSessions(sessions: readonly Session[]): Session {
  if (sessions.length === 0) throw new IncompatibleSessionsError("nothing to aggregate");

  const [first] = sessions as [Session, ...Session[]];

  for (const session of sessions) {
    if (session.security.toLowerCase() !== first.security.toLowerCase()) {
      throw new IncompatibleSessionsError("more than one security");
    }
    if (session.cash.toLowerCase() !== first.cash.toLowerCase()) {
      throw new IncompatibleSessionsError("more than one cash token");
    }
  }

  const quantity = new Map<Address, bigint>();
  const cash = new Map<Address, bigint>();

  for (const session of sessions) {
    for (const leg of session.legs) {
      quantity.set(leg.party, (quantity.get(leg.party) ?? 0n) + leg.quantityDelta);
      cash.set(leg.party, (cash.get(leg.party) ?? 0n) + leg.cashDelta);
    }
  }

  const legs: Leg[] = [...quantity.keys()]
    .map((party) => ({
      party,
      quantityDelta: quantity.get(party) ?? 0n,
      cashDelta: cash.get(party) ?? 0n,
    }))
    .sort((a, b) => (a.party.toLowerCase() < b.party.toLowerCase() ? -1 : 1));

  assertBalanced(legs);

  return { security: first.security, cash: first.cash, legs };
}

/** Transfers saved by aggregating, against settling each venue's session separately. */
export function aggregationSaving(
  sessions: readonly Session[],
): { perVenue: number; aggregated: number; ratio: number } {
  const moves = (session: Session): number =>
    session.legs.reduce(
      (sum, leg) => sum + (leg.quantityDelta !== 0n ? 1 : 0) + (leg.cashDelta !== 0n ? 1 : 0),
      0,
    );

  const perVenue = sessions.reduce((sum, session) => sum + moves(session), 0);
  const aggregated = moves(withoutFlatLegs(aggregateSessions(sessions)));
  const ratio = perVenue === 0 ? 0 : 1 - aggregated / perVenue;

  return { perVenue, aggregated, ratio };
}
