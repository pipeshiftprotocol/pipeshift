import assert from "node:assert/strict";
import { test } from "node:test";

import { describeListing, isActive, securityId, toBytes12 } from "../dist/registry.js";
import { Listing, type Address, type Security } from "../dist/types.js";

const CUSTODIAN = "0x000000000000000000000000000000000000c057" as Address;
const TOKEN = "0x0000000000000000000000000000000000000aaa" as Address;

function security(listing: Listing): Security {
  return {
    token: TOKEN,
    ticker: "AAPL",
    isin: "US0378331005",
    custodian: CUSTODIAN,
    decimals: 18,
    listing,
  };
}

test("toBytes12 right-pads to twelve bytes", () => {
  assert.equal(toBytes12("AAPL").length, 26);
  assert.ok(toBytes12("AAPL").startsWith("0x4141504c"));
});

test("toBytes12 rejects an oversized value", () => {
  assert.throws(() => toBytes12("THIRTEENCHARS"), RangeError);
});

test("toBytes12 accepts a full-length ISIN", () => {
  assert.equal(toBytes12("US0378331005").length, 26);
});

test("securityId is stable for the same ticker and ISIN", () => {
  assert.equal(securityId("AAPL", "US0378331005"), securityId("AAPL", "US0378331005"));
});

test("securityId separates different underlyings", () => {
  assert.notEqual(securityId("AAPL", "US0378331005"), securityId("TSLA", "US88160R1014"));
});

test("isActive only accepts an active listing", () => {
  assert.equal(isActive(security(Listing.Active)), true);
  assert.equal(isActive(security(Listing.Halted)), false);
  assert.equal(isActive(security(Listing.Delisted)), false);
  assert.equal(isActive(security(Listing.None)), false);
});

test("describeListing renders every state", () => {
  assert.equal(describeListing(Listing.Active), "active");
  assert.equal(describeListing(Listing.Halted), "halted");
  assert.equal(describeListing(Listing.Delisted), "delisted");
  assert.equal(describeListing(Listing.None), "unlisted");
});
