/**
 * End to end suite against a real node.
 *
 * Everything here runs against an actual JSON-RPC endpoint with real transactions,
 * real receipts and real revert data. The unit tests prove the logic; this proves
 * the SDK can drive the deployed contracts, which is a different claim.
 *
 * Run with:
 *   anvil &
 *   npm run devnet     # deploys and prints addresses
 *   npm run e2e
 *
 * Or in one shot: npm run e2e:full
 */

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  parseAbi,
  type Address,
  type PublicClient,
  type WalletClient,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { PipeshiftClient, instructionId, netTrades, validate, withoutFlatLegs } from "../dist/index.js";
import type { Deployment, Hex32, Instruction } from "../dist/index.js";

/** Anvil's deterministic accounts. Devnet only, these keys are public knowledge. */
const KEYS = {
  owner: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  venue: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  seller: "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  buyer: "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
  desk: "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
} as const;

const RPC_URL = process.env.PIPESHIFT_RPC_URL ?? "http://127.0.0.1:8545";
const CHAIN_ID = Number(process.env.PIPESHIFT_CHAIN_ID ?? 31337);

const devnet = defineChain({
  id: CHAIN_ID,
  name: "Pipeshift devnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});

const erc20 = parseAbi([
  "function approve(address spender, uint256 value) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
]);

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `${name} is not set. Run "npm run devnet" first, or use "npm run e2e:full".`,
    );
  }
  return value;
}

function walletFor(key: keyof typeof KEYS): WalletClient {
  return createWalletClient({
    account: privateKeyToAccount(KEYS[key]),
    chain: devnet,
    transport: http(RPC_URL),
  });
}

describe("settlement against a live node", () => {
  let publicClient: PublicClient;
  let deployment: Deployment;
  let security: Hex32;
  let equity: Address;
  let cash: Address;

  let seller: Address;
  let buyer: Address;
  let desk: Address;

  before(async () => {
    publicClient = createPublicClient({ chain: devnet, transport: http(RPC_URL) }) as PublicClient;

    // Fails loudly rather than silently skipping: a green run that never touched a
    // node would be worse than a red one.
    const chainId = await publicClient.getChainId();
    assert.equal(chainId, CHAIN_ID, "connected to the expected chain");

    deployment = {
      assetRegistry: requireEnv("PIPESHIFT_ASSET_REGISTRY") as Address,
      settlementEngine: requireEnv("PIPESHIFT_SETTLEMENT_ENGINE") as Address,
      nettingEngine: requireEnv("PIPESHIFT_NETTING_ENGINE") as Address,
    };
    security = requireEnv("PIPESHIFT_SECURITY") as Hex32;
    equity = requireEnv("PIPESHIFT_EQUITY") as Address;
    cash = requireEnv("PIPESHIFT_CASH") as Address;

    seller = privateKeyToAccount(KEYS.seller).address;
    buyer = privateKeyToAccount(KEYS.buyer).address;
    desk = privateKeyToAccount(KEYS.desk).address;

    // Approvals, from the accounts that own the balances.
    for (const [key, token] of [
      ["seller", equity],
      ["buyer", cash],
      ["seller", cash],
      ["buyer", equity],
      ["desk", equity],
      ["desk", cash],
    ] as const) {
      const wallet = walletFor(key);
      for (const spender of [deployment.settlementEngine, deployment.nettingEngine]) {
        const hash = await wallet.writeContract({
          address: token,
          abi: erc20,
          functionName: "approve",
          args: [spender, 2n ** 255n],
          chain: devnet,
          account: wallet.account!,
        });
        await publicClient.waitForTransactionReceipt({ hash });
      }
    }
  });

  it("reads the registry it was pointed at", async () => {
    const client = new PipeshiftClient({ publicClient, deployment });

    const record = await client.securityOf(security);
    assert.equal(record.ticker, "AAPL", "canonical record resolves");
    assert.equal(record.token.toLowerCase(), equity.toLowerCase());
    assert.equal(await client.isSettleable(security), true);
    assert.ok((await client.listedCount()) >= 1n);
  });

  it("refuses to write without a wallet client", async () => {
    const reader = new PipeshiftClient({ publicClient, deployment });
    await assert.rejects(() => reader.settle(("0x" + "11".repeat(32)) as Hex32), /wallet client/);
  });

  it("settles a matched trade and moves both legs", async () => {
    const venueClient = new PipeshiftClient({
      publicClient,
      walletClient: walletFor("venue"),
      deployment,
    });

    const balancesBefore = await balances(publicClient, { equity, cash, seller, buyer });

    const instruction: Instruction = {
      security,
      cash,
      seller,
      buyer,
      quantity: 400n * 10n ** 18n,
      consideration: 82_000n * 10n ** 6n,
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3_600),
      venue: privateKeyToAccount(KEYS.venue).address,
    };

    assert.deepEqual(validate(instruction, BigInt(Math.floor(Date.now() / 1000))), []);

    const { hash: affirmHash, id } = await venueClient.affirm(instruction);
    await publicClient.waitForTransactionReceipt({ hash: affirmHash });

    assert.equal(id, instructionId(instruction), "the id matches what the contract stores");

    const settleHash = await venueClient.settle(id);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: settleHash });
    assert.equal(receipt.status, "success");

    const balancesAfter = await balances(publicClient, { equity, cash, seller, buyer });

    assert.equal(
      balancesAfter.sellerEquity,
      balancesBefore.sellerEquity - instruction.quantity,
      "seller delivered the security leg",
    );
    assert.equal(
      balancesAfter.buyerEquity,
      balancesBefore.buyerEquity + instruction.quantity,
      "buyer received the security leg",
    );
    assert.equal(
      balancesAfter.sellerCash,
      balancesBefore.sellerCash + instruction.consideration,
      "seller received the cash leg",
    );
    assert.equal(
      balancesAfter.buyerCash,
      balancesBefore.buyerCash - instruction.consideration,
      "buyer delivered the cash leg",
    );
  });

  it("reverts a settlement whose cash leg cannot move", async () => {
    const venueClient = new PipeshiftClient({
      publicClient,
      walletClient: walletFor("venue"),
      deployment,
    });

    // A buyer with no cash balance and no approval for this amount.
    const brokeBuyer = privateKeyToAccount(
      "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",
    ).address;

    const instruction: Instruction = {
      security,
      cash,
      seller,
      buyer: brokeBuyer,
      quantity: 1n * 10n ** 18n,
      consideration: 500n * 10n ** 6n,
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3_600),
      venue: privateKeyToAccount(KEYS.venue).address,
    };

    const before = await balances(publicClient, { equity, cash, seller, buyer });

    const { hash } = await venueClient.affirm(instruction);
    await publicClient.waitForTransactionReceipt({ hash });

    const id = instructionId(instruction);
    await assert.rejects(() => venueClient.settle(id), "settlement must revert");

    const after = await balances(publicClient, { equity, cash, seller, buyer });
    assert.equal(after.sellerEquity, before.sellerEquity, "the security leg did not move");
  });

  it("settles a netting session computed by the sdk", async () => {
    const venueClient = new PipeshiftClient({
      publicClient,
      walletClient: walletFor("venue"),
      deployment,
    });

    const before = await balances(publicClient, { equity, cash, seller, buyer });
    const sessionsBefore = await venueClient.grossTradesNetted();

    // Two trades that mostly offset: 400 out, 380 back.
    const session = netTrades(security, cash, [
      { seller, buyer: desk, quantity: 400n * 10n ** 18n, consideration: 82_000n * 10n ** 6n },
      { seller: desk, buyer: seller, quantity: 380n * 10n ** 18n, consideration: 78_090n * 10n ** 6n },
    ]);

    const trimmed = withoutFlatLegs(session);
    assert.equal(trimmed.legs.length, 2, "two desks with a net position");

    const hash = await venueClient.settleSession(session, 2);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    assert.equal(receipt.status, "success");

    const after = await balances(publicClient, { equity, cash, seller, buyer });

    // The seller sold 400 and bought back 380, so 20 net leaves the account.
    assert.equal(
      after.sellerEquity,
      before.sellerEquity - 20n * 10n ** 18n,
      "only the net quantity moved",
    );
    assert.equal(
      await venueClient.grossTradesNetted(),
      sessionsBefore + 2n,
      "gross trades counter advanced",
    );
  });

  it("rejects an unbalanced session before it costs gas", async () => {
    const venueClient = new PipeshiftClient({
      publicClient,
      walletClient: walletFor("venue"),
      deployment,
    });

    const unbalanced = {
      security,
      cash,
      legs: [
        { party: seller, quantityDelta: 5n, cashDelta: 0n },
        { party: desk, quantityDelta: -4n, cashDelta: 0n },
      ],
    };

    await assert.rejects(() => venueClient.settleSession(unbalanced, 1), /does not net to zero/);
  });

  after(() => {
    // Nothing to tear down: the suite holds no resources and the node is the caller's.
  });
});

async function balances(
  client: PublicClient,
  addresses: { equity: Address; cash: Address; seller: Address; buyer: Address },
): Promise<{ sellerEquity: bigint; buyerEquity: bigint; sellerCash: bigint; buyerCash: bigint }> {
  const read = (token: Address, account: Address): Promise<bigint> =>
    client.readContract({ address: token, abi: erc20, functionName: "balanceOf", args: [account] });

  const [sellerEquity, buyerEquity, sellerCash, buyerCash] = await Promise.all([
    read(addresses.equity, addresses.seller),
    read(addresses.equity, addresses.buyer),
    read(addresses.cash, addresses.seller),
    read(addresses.cash, addresses.buyer),
  ]);

  return { sellerEquity, buyerEquity, sellerCash, buyerCash };
}
