/**
 * Instruction helpers.
 *
 * The instruction id is computed the same way on chain and off chain, so a venue
 * can reference a settlement before it has been submitted.
 */

import { encodeAbiParameters, keccak256 } from "viem";
import { Status, type Hex32, type Instruction } from "./types.js";

const INSTRUCTION_ABI = [
  { type: "bytes32" },
  { type: "address" },
  { type: "address" },
  { type: "address" },
  { type: "uint256" },
  { type: "uint256" },
  { type: "uint64" },
  { type: "address" },
] as const;

/** Computes the deterministic id of an instruction. */
export function instructionId(instruction: Instruction): Hex32 {
  return keccak256(
    encodeAbiParameters(INSTRUCTION_ABI, [
      instruction.security,
      instruction.cash,
      instruction.seller,
      instruction.buyer,
      instruction.quantity,
      instruction.consideration,
      instruction.deadline,
      instruction.venue,
    ]),
  );
}

/** Reasons an instruction cannot be affirmed. */
export type Rejection =
  | "zero-quantity"
  | "zero-consideration"
  | "deadline-in-past"
  | "self-trade";

/**
 * Checks an instruction against the rules the engine enforces.
 *
 * Returns every problem rather than the first one, so a venue can fix a whole
 * batch in one pass instead of discovering issues one revert at a time.
 */
export function validate(instruction: Instruction, now: bigint): Rejection[] {
  const rejections: Rejection[] = [];

  if (instruction.quantity <= 0n) rejections.push("zero-quantity");
  if (instruction.consideration <= 0n) rejections.push("zero-consideration");
  if (instruction.deadline <= now) rejections.push("deadline-in-past");
  if (instruction.seller === instruction.buyer) rejections.push("self-trade");

  return rejections;
}

/** Whether an instruction can still be settled at the given time. */
export function isSettleable(status: Status, deadline: bigint, now: bigint): boolean {
  return status === Status.Affirmed && now <= deadline;
}

/** Implied price per whole security unit, in cash base units. */
export function impliedPrice(instruction: Instruction, securityDecimals: number): bigint {
  if (instruction.quantity === 0n) throw new RangeError("quantity must be positive");
  return (instruction.consideration * 10n ** BigInt(securityDecimals)) / instruction.quantity;
}
