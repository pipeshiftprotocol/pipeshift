import assert from "node:assert/strict";
import { test } from "node:test";

import { impliedPrice, instructionId, isSettleable, validate } from "../dist/instruction.js";
import { Status, type Address, type Hex32, type Instruction } from "../dist/types.js";

const SECURITY = "0x1111111111111111111111111111111111111111111111111111111111111111" as Hex32;
const CASH = "0x2222222222222222222222222222222222222222" as Address;
const SELLER = "0x000000000000000000000000000000000000000a" as Address;
const BUYER = "0x000000000000000000000000000000000000000b" as Address;
const VENUE = "0x000000000000000000000000000000000000000f" as Address;

function instruction(overrides: Partial<Instruction> = {}): Instruction {
  return {
    security: SECURITY,
    cash: CASH,
    seller: SELLER,
    buyer: BUYER,
    quantity: 400_000000000000000000n,
    consideration: 82_000_000000n,
    deadline: 2_000_000_000n,
    venue: VENUE,
    ...overrides,
  };
}

test("instructionId is stable for identical instructions", () => {
  assert.equal(instructionId(instruction()), instructionId(instruction()));
});

test("instructionId changes when any field changes", () => {
  const base = instructionId(instruction());

  assert.notEqual(base, instructionId(instruction({ quantity: 401_000000000000000000n })));
  assert.notEqual(base, instructionId(instruction({ buyer: VENUE })));
  assert.notEqual(base, instructionId(instruction({ deadline: 2_000_000_001n })));
});
