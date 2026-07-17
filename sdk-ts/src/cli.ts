#!/usr/bin/env node
/**
 * Pipeshift command line.
 *
 * Every command is offline and read-only. Nothing here signs a transaction or
 * reaches a private key, so it is safe to run against production data while
 * reasoning about a session.
 */

import { readFileSync } from "node:fs";
import { compressionOf, netTrades, withoutFlatLegs } from "./netting.js";
import { impliedPrice, instructionId, validate } from "./instruction.js";
import { securityId } from "./registry.js";
import type { Instruction, Trade } from "./types.js";

const USAGE = `pipeshift <command> [options]

Commands
  net <file.json>          Collapse a trade file into one net position per party
  id <file.json>           Compute the settlement id of an instruction
  validate <file.json>     Check an instruction against the engine rules
  security <ticker> <isin> Compute the canonical registry id for an underlying
  help                     Show this message

Trade file
  { "security": "0x...", "cash": "0x...",
    "trades": [{ "seller": "0x...", "buyer": "0x...",
                 "quantity": "400", "consideration": "82000" }] }

Amounts are strings in base units. They are parsed as bigint, never as float.
`;

/** Parses a decimal string into bigint, rejecting anything lossy. */
function toBigInt(value: unknown, field: string): bigint {
  if (typeof value === "bigint") return value;
  if (typeof value === "number") {
    throw new TypeError(`${field} must be a string, not a number, to avoid float rounding`);
  }
  if (typeof value !== "string" || !/^-?\d+$/.test(value)) {
    throw new TypeError(`${field} must be a decimal string in base units`);
  }
  return BigInt(value);
}

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

function parseTrades(raw: unknown): Trade[] {
  if (!Array.isArray(raw)) throw new TypeError("trades must be an array");

  return raw.map((entry, index) => {
    const trade = entry as Record<string, unknown>;
    return {
      seller: trade.seller as Trade["seller"],
      buyer: trade.buyer as Trade["buyer"],
      quantity: toBigInt(trade.quantity, `trades[${index}].quantity`),
      consideration: toBigInt(trade.consideration, `trades[${index}].consideration`),
    };
  });
}

function parseInstruction(raw: Record<string, unknown>): Instruction {
  return {
    security: raw.security as Instruction["security"],
    cash: raw.cash as Instruction["cash"],
    seller: raw.seller as Instruction["seller"],
    buyer: raw.buyer as Instruction["buyer"],
    quantity: toBigInt(raw.quantity, "quantity"),
    consideration: toBigInt(raw.consideration, "consideration"),
    deadline: toBigInt(raw.deadline, "deadline"),
    venue: raw.venue as Instruction["venue"],
  };
}

function commandNet(path: string): number {
  const file = readJson(path);
  const trades = parseTrades(file.trades);

  const session = netTrades(
    file.security as `0x${string}`,
    file.cash as `0x${string}`,
    trades,
  );
  const active = withoutFlatLegs(session);
  const report = compressionOf(session, trades.length);

  console.log(`security        ${session.security}`);
  console.log(`cash            ${session.cash}`);
  console.log(`trades in       ${trades.length}`);
  console.log(`parties         ${session.legs.length}`);
  console.log(`parties moving  ${active.legs.length}`);
  console.log(`transfers gross ${report.grossTransfers}`);
  console.log(`transfers net   ${report.netTransfers}`);
  console.log(`compression     ${(report.ratio * 100).toFixed(2)}%`);
  console.log("");
  console.log("party                                      quantity            cash");

  for (const leg of active.legs) {
    const quantity = leg.quantityDelta.toString().padStart(18);
    const cash = leg.cashDelta.toString().padStart(15);
    console.log(`${leg.party}  ${quantity}  ${cash}`);
  }

  return 0;
}

function commandId(path: string): number {
  const instruction = parseInstruction(readJson(path));
  console.log(instructionId(instruction));
  return 0;
}

function commandValidate(path: string): number {
  const instruction = parseInstruction(readJson(path));
  const now = BigInt(Math.floor(Date.now() / 1000));
  const rejections = validate(instruction, now);

  if (rejections.length === 0) {
    console.log("ok");
    console.log(`id             ${instructionId(instruction)}`);
    console.log(`implied price  ${impliedPrice(instruction, 18)}`);
    return 0;
  }

  for (const rejection of rejections) {
    console.error(`reject: ${rejection}`);
  }
  return 1;
}

function commandSecurity(ticker: string, isin: string): number {
  console.log(securityId(ticker, isin));
  return 0;
}

export function run(argv: readonly string[]): number {
  const [command, ...rest] = argv;

  try {
    switch (command) {
      case "net":
        if (!rest[0]) throw new TypeError("net requires a trade file");
        return commandNet(rest[0]);
      case "id":
        if (!rest[0]) throw new TypeError("id requires an instruction file");
        return commandId(rest[0]);
      case "validate":
        if (!rest[0]) throw new TypeError("validate requires an instruction file");
        return commandValidate(rest[0]);
      case "security":
        if (!rest[0] || !rest[1]) throw new TypeError("security requires a ticker and an ISIN");
        return commandSecurity(rest[0], rest[1]);
      case "help":
      case "--help":
      case undefined:
        console.log(USAGE);
        return 0;
      default:
        console.error(`unknown command: ${command}`);
        console.error(USAGE);
        return 1;
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  process.exit(run(process.argv.slice(2)));
}
