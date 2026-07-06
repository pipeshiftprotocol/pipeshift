// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {SettlementEngine} from "../src/SettlementEngine.sol";
import {NettingEngine} from "../src/NettingEngine.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";

/// @notice Deploys the registry first, then both engines pointed at it.
/// @dev Run against Robinhood Chain with:
///      forge script script/Deploy.s.sol --rpc-url $PIPESHIFT_RPC_URL --broadcast
contract Deploy is Script {
    function run()
        external
        returns (AssetRegistry registry, SettlementEngine settlement, NettingEngine netting)
    {
        address owner = vm.envAddress("PIPESHIFT_OWNER");

        vm.startBroadcast();

        registry = new AssetRegistry(owner);
        settlement = new SettlementEngine(owner, IAssetRegistry(address(registry)));
        netting = new NettingEngine(owner, IAssetRegistry(address(registry)));

        vm.stopBroadcast();

        console.log("AssetRegistry   ", address(registry));
        console.log("SettlementEngine", address(settlement));
        console.log("NettingEngine   ", address(netting));
    }
}
