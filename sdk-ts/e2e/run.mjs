#!/usr/bin/env node
/**
 * One shot end to end runner.
 *
 * Starts anvil, deploys the devnet fixture with forge, exports the printed
 * addresses, runs the e2e suite against it, then shuts the node down. Every step
 * is a real process against a real JSON-RPC endpoint.
 */

import { spawn, spawnSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

const RPC_PORT = process.env.PIPESHIFT_E2E_PORT ?? "8545";
const RPC_URL = `http://127.0.0.1:${RPC_PORT}`;

/**
 * Fork a real network when PIPESHIFT_FORK_URL is set.
 *
 * A fork runs the contracts against the chain's actual id, gas parameters and EVM
 * revision, which a bare anvil does not. That is the difference between "the code
 * works" and "the code works on Robinhood Chain".
 */
const FORK_URL = process.env.PIPESHIFT_FORK_URL;

// Anvil's deterministic accounts, matched to the roles in the suite.
const ACCOUNTS = {
  PIPESHIFT_OWNER: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  PIPESHIFT_VENUE: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  PIPESHIFT_SELLER: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
  PIPESHIFT_BUYER: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
  PIPESHIFT_DESK: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65",
};
const OWNER_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

function which(binary) {
  return spawnSync("which", [binary], { encoding: "utf8" }).status === 0;
}

async function waitForNode(url, attempts = 60) {
  for (let i = 0; i < attempts; i += 1) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
      });
      if (response.ok) return true;
    } catch {
      // not up yet
    }
    await sleep(250);
  }
  return false;
}

function fail(message) {
  console.error(`\n${message}\n`);
  process.exit(1);
}

if (!which("anvil") || !which("forge")) {
  fail("anvil and forge are required. Install Foundry: https://getfoundry.sh");
}

const anvilArgs = ["--port", RPC_PORT, "--silent"];
if (FORK_URL) anvilArgs.push("--fork-url", FORK_URL);

console.error(
  FORK_URL
    ? `starting anvil on port ${RPC_PORT}, forking ${FORK_URL}`
    : `starting anvil on port ${RPC_PORT}`,
);
const anvil = spawn("anvil", anvilArgs, { stdio: "inherit" });

const shutdown = () => {
  if (!anvil.killed) anvil.kill("SIGTERM");
};
process.on("exit", shutdown);
process.on("SIGINT", () => {
  shutdown();
  process.exit(130);
});

if (!(await waitForNode(RPC_URL, FORK_URL ? 240 : 60))) {
  shutdown();
  fail("anvil did not come up");
}

// Read the id from the node rather than assuming it: on a fork it is the forked
// chain's id, and a mismatch here is the failure the suite should report.
const chainIdResponse = await fetch(RPC_URL, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
});
const CHAIN_ID = String(Number((await chainIdResponse.json()).result));
console.error(`chain id ${CHAIN_ID}`);

console.error("deploying the devnet fixture");
const deploy = spawnSync(
  "forge",
  [
    "script",
    "script/Devnet.s.sol",
    "--rpc-url",
    RPC_URL,
    "--broadcast",
    "--private-key",
    OWNER_KEY,
    "-vv",
  ],
  {
    cwd: new URL("../../contracts", import.meta.url).pathname,
    encoding: "utf8",
    env: { ...process.env, ...ACCOUNTS },
  },
);

if (deploy.status !== 0) {
  console.error(deploy.stdout ?? "");
  console.error(deploy.stderr ?? "");
  shutdown();
  fail("the devnet deployment failed");
}

// The script prints KEY=value lines; lift them into the environment for the suite.
const addresses = {};
for (const line of (deploy.stdout ?? "").split("\n")) {
  const match = line.match(/(PIPESHIFT_[A-Z_]+)=(0x[0-9a-fA-F]+)/);
  if (match) addresses[match[1]] = match[2];
}

const required = [
  "PIPESHIFT_ASSET_REGISTRY",
  "PIPESHIFT_SETTLEMENT_ENGINE",
  "PIPESHIFT_NETTING_ENGINE",
  "PIPESHIFT_EQUITY",
  "PIPESHIFT_CASH",
  "PIPESHIFT_SECURITY",
];
const missing = required.filter((key) => !addresses[key]);
if (missing.length > 0) {
  console.error(deploy.stdout ?? "");
  shutdown();
  fail(`the deployment did not report: ${missing.join(", ")}`);
}

for (const [key, value] of Object.entries(addresses)) {
  console.error(`  ${key}=${value}`);
}

console.error("\nrunning the e2e suite\n");
/* The default TAP output is thorough and noisy. A demo or a terminal run reads
   better with the spec reporter, so allow it to be selected per run. */
const reporter = process.env.PIPESHIFT_TEST_REPORTER ?? "tap";

const suite = spawnSync(
  process.execPath,
  ["--test", `--test-reporter=${reporter}`, "--experimental-strip-types", "e2e/settle.e2e.ts"],
  {
    stdio: "inherit",
    env: {
      ...process.env,
      ...addresses,
      PIPESHIFT_RPC_URL: RPC_URL,
      PIPESHIFT_CHAIN_ID: CHAIN_ID,
    },
  },
);

shutdown();
process.exit(suite.status ?? 1);
