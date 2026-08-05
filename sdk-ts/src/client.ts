/**
 * Typed clients over the deployed contracts.
 *
 * Reads go through a viem public client. Writes take a wallet client, so the SDK
 * never touches a private key itself and nothing here can sign on its own.
 */

import type { Address as ViemAddress, Hash, PublicClient, WalletClient } from "viem";
import { assetRegistryAbi, nettingEngineAbi, settlementEngineAbi } from "./abi.js";
import { instructionId } from "./instruction.js";
import { assertBalanced, withoutFlatLegs } from "./netting.js";
import {
  Listing,
  Status,
  type Address,
  type Fill,
  type Hex32,
  type Instruction,
  type Security,
  type Session,
} from "./types.js";

/** Addresses of the deployed Pipeshift contracts. */
export interface Deployment {
  settlementEngine: Address;
  nettingEngine: Address;
  assetRegistry: Address;
}

export interface ClientOptions {
  publicClient: PublicClient;
  walletClient?: WalletClient;
  deployment: Deployment;
}

/** Thrown when a write is attempted without a wallet client. */
export class ReadOnlyClientError extends Error {
  constructor(operation: string) {
    super(`${operation} requires a wallet client`);
    this.name = "ReadOnlyClientError";
  }
}

export class PipeshiftClient {
  readonly deployment: Deployment;

  private readonly publicClient: PublicClient;
  private readonly walletClient?: WalletClient;

  constructor(options: ClientOptions) {
    this.publicClient = options.publicClient;
    this.walletClient = options.walletClient;
    this.deployment = options.deployment;
  }

  /** Whether this client can submit transactions. */
  get canWrite(): boolean {
    return this.walletClient !== undefined;
  }

  /** Reads the canonical record for a security id. */
  async securityOf(id: Hex32): Promise<Security> {
    const raw = await this.publicClient.readContract({
      address: this.deployment.assetRegistry as ViemAddress,
      abi: assetRegistryAbi,
      functionName: "securityOf",
      args: [id],
    });

    return {
      token: raw.token as Address,
      ticker: trimBytes(raw.ticker),
      isin: trimBytes(raw.isin),
      custodian: raw.custodian as Address,
      decimals: raw.decimals,
      listing: raw.listing as Listing,
    };
  }

  /** Whether a security is listed and currently settleable. */
  async isSettleable(id: Hex32): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.deployment.assetRegistry as ViemAddress,
      abi: assetRegistryAbi,
      functionName: "isSettleable",
      args: [id],
    });
  }

  /** Number of securities listed in the registry. */
  async listedCount(): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.deployment.assetRegistry as ViemAddress,
      abi: assetRegistryAbi,
      functionName: "count",
    });
  }

  /** Number of instructions the engine has settled. */
  async settledCount(): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.deployment.settlementEngine as ViemAddress,
      abi: settlementEngineAbi,
      functionName: "settledCount",
    });
  }

  /** Gross trades collapsed by the netting engine so far. */
  async grossTradesNetted(): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.deployment.nettingEngine as ViemAddress,
      abi: nettingEngineAbi,
      functionName: "grossTradesNetted",
    });
  }

  /** Submits a matched trade for settlement. */
  async affirm(instruction: Instruction): Promise<{ hash: Hash; id: Hex32 }> {
    const wallet = this.requireWallet("affirm");

    const hash = await wallet.writeContract({
      address: this.deployment.settlementEngine as ViemAddress,
      abi: settlementEngineAbi,
      functionName: "affirm",
      args: [instruction],
      chain: wallet.chain,
      account: wallet.account!,
    });

    return { hash, id: instructionId(instruction) };
  }

  /** Reads how much of an instruction has been delivered so far. */
  async fillOf(id: Hex32): Promise<Fill> {
    const [quantity, consideration, remaining] = await this.publicClient.readContract({
      address: this.deployment.settlementEngine as ViemAddress,
      abi: settlementEngineAbi,
      functionName: "fillOf",
      args: [id],
    });

    return { quantity, consideration, remaining };
  }

  /**
   * Settles part of an instruction.
   *
   * Inventory arrives late and in pieces, so an instruction can be closed over
   * several fills. Each fill is atomic across both legs, and the fill that closes
   * the instruction takes the remaining consideration rather than a rounded share,
   * so slicing never changes what the parties end up with.
   */
  async settlePartial(id: Hex32, quantity: bigint): Promise<Hash> {
    const wallet = this.requireWallet("settlePartial");
    if (quantity <= 0n) throw new RangeError("quantity must be positive");

    return wallet.writeContract({
      address: this.deployment.settlementEngine as ViemAddress,
      abi: settlementEngineAbi,
      functionName: "settlePartial",
      args: [id, quantity],
      chain: wallet.chain,
      account: wallet.account!,
    });
  }

  /** Settles one affirmed instruction. */
  async settle(id: Hex32): Promise<Hash> {
    const wallet = this.requireWallet("settle");

    return wallet.writeContract({
      address: this.deployment.settlementEngine as ViemAddress,
      abi: settlementEngineAbi,
      functionName: "settle",
      args: [id],
      chain: wallet.chain,
      account: wallet.account!,
    });
  }

  /**
   * Settles a netting session.
   *
   * Flat legs are dropped and the balance is checked locally first, so an
   * unbalanced session fails before it costs gas.
   */
  async settleSession(session: Session, grossTrades: number): Promise<Hash> {
    const wallet = this.requireWallet("settleSession");

    assertBalanced(session.legs);
    const trimmed = withoutFlatLegs(session);

    return wallet.writeContract({
      address: this.deployment.nettingEngine as ViemAddress,
      abi: nettingEngineAbi,
      functionName: "settleSession",
      args: [trimmed, BigInt(grossTrades)],
      chain: wallet.chain,
      account: wallet.account!,
    });
  }

  /**
   * Settles one session covering several venues.
   *
   * The venues are recorded on chain for audit, and the caller has to be one of
   * them, so a group can nominate whichever member submits without letting an
   * outsider settle somebody else's book.
   */
  async settleAggregated(
    session: Session,
    venues: readonly Address[],
    grossTrades: number,
  ): Promise<Hash> {
    const wallet = this.requireWallet("settleAggregated");

    assertBalanced(session.legs);
    const trimmed = withoutFlatLegs(session);

    return wallet.writeContract({
      address: this.deployment.nettingEngine as ViemAddress,
      abi: nettingEngineAbi,
      functionName: "settleAggregated",
      args: [trimmed, venues as ViemAddress[], BigInt(grossTrades)],
      chain: wallet.chain,
      account: wallet.account!,
    });
  }

  private requireWallet(operation: string): WalletClient {
    if (!this.walletClient) throw new ReadOnlyClientError(operation);
    return this.walletClient;
  }
}

/** Strips right-padding from a fixed-size bytes field. */
function trimBytes(value: string): string {
  const hex = value.startsWith("0x") ? value.slice(2) : value;
  let out = "";

  for (let i = 0; i < hex.length; i += 2) {
    const code = Number.parseInt(hex.slice(i, i + 2), 16);
    if (code === 0) break;
    out += String.fromCharCode(code);
  }

  return out;
}

export { Status };
