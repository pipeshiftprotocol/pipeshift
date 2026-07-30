#!/usr/bin/env bash
#
# Scripted demo of the settlement path, for screen recording.
#
# Types each command out, runs it for real, and pauses long enough to read the
# output. Nothing here is faked: the netting numbers come from the CLI and the
# settlement run deploys contracts to a node and sends transactions.
#
#   bash scripts/demo.sh          local node
#   FORK=1 bash scripts/demo.sh   fork of Robinhood Chain
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$ROOT/sdk-ts"

MINT="\033[38;2;80;247;195m"
DIM="\033[38;2;110;120;116m"
BOLD="\033[1m"
OFF="\033[0m"

TYPE_SPEED="${TYPE_SPEED:-0.012}"
READ_PAUSE="${READ_PAUSE:-2.4}"

# Types a command character by character so the recording looks live.
type_out() {
  printf "${MINT}\$${OFF} "
  local text="$1"
  for ((i = 0; i < ${#text}; i++)); do
    printf "%s" "${text:i:1}"
    sleep "$TYPE_SPEED"
  done
  printf "\n"
  sleep 0.35
}

say() {
  printf "\n${DIM}%s${OFF}\n\n" "$1"
  sleep 1.1
}

run() {
  type_out "$1"
  eval "$1"
  sleep "$READ_PAUSE"
}

clear

printf "${BOLD}Pipeshift${OFF} ${DIM}settlement layer for tokenized equities${OFF}\n"
sleep 1.4

# ----------------------------------------------------------------- netting
say "Four matched trades between three desks. Settled gross that is eight transfers."

cd "$SDK"
run "cat examples/session.json | head -12"

say "The CLI collapses them into one net position per desk."

run "node dist/cli.js net examples/session.json"

say "Half the transfers disappear, and one desk ends flat and moves nothing at all."

# ----------------------------------------------------------------- settlement
say "Now the same path on a real node: deploy the contracts, then settle against them."

if [ "${FORK:-0}" = "1" ]; then
  say "Forking Robinhood Chain, so the contracts run with the chain's own id and gas."
  PIPESHIFT_TEST_REPORTER=spec run "npm run --silent e2e:fork"
else
  PIPESHIFT_TEST_REPORTER=spec run "npm run --silent e2e:full"
fi

say "Six settlement tests against a live node. Both legs move, or neither does."

printf "\n${MINT}pipeshift.trade${OFF}\n\n"
