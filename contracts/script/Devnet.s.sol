// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {SettlementEngine} from "../src/SettlementEngine.sol";
import {NettingEngine} from "../src/NettingEngine.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {DemoToken} from "./demo/DemoToken.sol";

/// @notice Brings up a complete working deployment on a local node.
/// @dev Deploys the three contracts plus two demo tokens, lists one security, registers a
///      venue and funds the parties, so the end to end suite has something real to settle
///      against. Devnet only: the demo tokens have an unguarded mint.
///
///      forge script script/Devnet.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
contract Devnet is Script {
    function run() external {
        address deployer = vm.envAddress("PIPESHIFT_OWNER");
        address venue = vm.envAddress("PIPESHIFT_VENUE");
        address seller = vm.envAddress("PIPESHIFT_SELLER");
        address buyer = vm.envAddress("PIPESHIFT_BUYER");
        address custodian = vm.envOr("PIPESHIFT_CUSTODIAN", deployer);
        address desk = vm.envAddress("PIPESHIFT_DESK");

        vm.startBroadcast();

        AssetRegistry registry = new AssetRegistry(deployer);
        SettlementEngine settlement = new SettlementEngine(deployer, IAssetRegistry(address(registry)));
        NettingEngine netting = new NettingEngine(deployer, IAssetRegistry(address(registry)));

        DemoToken equity = new DemoToken("Pipeshift Apple", "pAAPL", 18);
        DemoToken cash = new DemoToken("USD Coin", "USDC", 6);

        bytes32 security = registry.list(
            IAssetRegistry.Security({
                token: address(equity),
                ticker: bytes12("AAPL"),
                isin: bytes12("US0378331005"),
                custodian: custodian,
                decimals: 18,
                listing: IAssetRegistry.Listing.Active
            })
        );

        settlement.registerVenue(venue);
        settlement.setCashAccepted(address(cash), true);
        netting.registerVenue(venue);

        // Fund every role. A netting session moves value in both directions for every
        // participant, so each account needs a balance on both legs, not just the one
        // its side of the first trade happens to need.
        address[3] memory funded = [seller, buyer, desk];
        for (uint256 i; i < funded.length; ++i) {
            equity.mint(funded[i], 10_000e18);
            cash.mint(funded[i], 5_000_000e6);
        }

        vm.stopBroadcast();

        console.log("PIPESHIFT_ASSET_REGISTRY=%s", address(registry));
        console.log("PIPESHIFT_SETTLEMENT_ENGINE=%s", address(settlement));
        console.log("PIPESHIFT_NETTING_ENGINE=%s", address(netting));
        console.log("PIPESHIFT_EQUITY=%s", address(equity));
        console.log("PIPESHIFT_CASH=%s", address(cash));
        console.log("PIPESHIFT_SECURITY=%s", vm.toString(security));
    }
}
