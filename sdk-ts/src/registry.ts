/**
 * Canonical registry helpers.
 *
 * Ids are derived from ticker and ISIN, not from the token address, so a
 * reissued token keeps its canonical identity and its settlement history.
 */

import { keccak256, encodePacked, stringToHex } from "viem";
import { Listing, type Hex32, type Security } from "./types.js";

/** Pads an ASCII string into the bytes12 layout the registry uses. */
export function toBytes12(value: string): Hex32 {
  if (value.length > 12) throw new RangeError(`"${value}" exceeds 12 bytes`);
  return stringToHex(value, { size: 12 });
}

/** Computes the canonical id for a ticker and ISIN pair. */
export function securityId(ticker: string, isin: string): Hex32 {
  return keccak256(encodePacked(["bytes12", "bytes12"], [toBytes12(ticker), toBytes12(isin)]));
}

/** Whether a security is currently settleable. */
export function isActive(security: Security): boolean {
  return security.listing === Listing.Active;
}

/** Human-readable listing state, for logs and CLI output. */
export function describeListing(listing: Listing): string {
  switch (listing) {
    case Listing.Active:
      return "active";
    case Listing.Halted:
      return "halted";
    case Listing.Delisted:
      return "delisted";
    default:
      return "unlisted";
  }
}
