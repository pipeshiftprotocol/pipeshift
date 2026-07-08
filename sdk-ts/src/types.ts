/**
 * Core types for the Pipeshift settlement SDK.
 *
 * Amounts are always bigint in base units. Floating point never touches a
 * settlement amount, because a rounding error here is a real position break.
 */

/**
 * Lifecycle of a settlement instruction, mirroring the on-chain enum.
 *
 * Declared as a const object rather than a TypeScript enum so the module runs
 * unmodified under Node type stripping and adds nothing to the bundle.
 */
export const Status = {
  None: 0,
  Affirmed: 1,
  Settled: 2,
  Cancelled: 3,
  Expired: 4,
} as const;

export type Status = (typeof Status)[keyof typeof Status];

/** Listing state of a security in the canonical registry. */
export const Listing = {
  None: 0,
  Active: 1,
  Halted: 2,
  Delisted: 3,
} as const;

export type Listing = (typeof Listing)[keyof typeof Listing];

export type Address = `0x${string}`;
export type Hex32 = `0x${string}`;

/** A matched trade, ready to be affirmed for settlement. */
export interface Instruction {
  /** Canonical registry id of the tokenized equity. */
  security: Hex32;
  /** Token used for the cash leg. */
  cash: Address;
  /** Party delivering the security leg. */
  seller: Address;
  /** Party delivering the cash leg. */
  buyer: Address;
  /** Security amount, in security base units. */
  quantity: bigint;
  /** Cash amount, in cash base units. */
  consideration: bigint;
  /** Unix seconds after which the instruction can no longer settle. */
  deadline: bigint;
  /** Venue that matched the trade. */
  venue: Address;
}

/** One party's net position change inside a netting session. */
export interface Leg {
  party: Address;
  quantityDelta: bigint;
  cashDelta: bigint;
}

/** A batch of legs settled as a single unit. */
export interface Session {
  security: Hex32;
  cash: Address;
  legs: Leg[];
}

/** Canonical registry record for one tokenized equity. */
export interface Security {
  token: Address;
  ticker: string;
  isin: string;
  custodian: Address;
  decimals: number;
  listing: Listing;
}

/** Result of comparing gross settlement against a netted session. */
export interface CompressionReport {
  /** Transfers gross settlement would perform. */
  grossTransfers: number;
  /** Transfers the netted session performs. */
  netTransfers: number;
  /** Parties whose net position is flat and who therefore move nothing. */
  flatParties: number;
  /** Share of transfers removed, between 0 and 1. */
  ratio: number;
}

/** A trade as reported by a venue, before netting. */
export interface Trade {
  seller: Address;
  buyer: Address;
  quantity: bigint;
  consideration: bigint;
}
