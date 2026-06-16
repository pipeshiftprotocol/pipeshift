// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {Owned} from "../src/libraries/Owned.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AssetRegistryTest is Test {
    AssetRegistry internal registry;
    MockERC20 internal apple;
    MockERC20 internal tesla;

    address internal owner = address(0xA11CE);
    address internal custodian = address(0xC057);
    address internal outsider = address(0xBAD);

    function setUp() public {
        registry = new AssetRegistry(owner);
        apple = new MockERC20("Pipeshift Apple", "pAAPL", 18);
        tesla = new MockERC20("Pipeshift Tesla", "pTSLA", 18);
    }

    function _security(address token, bytes12 ticker, bytes12 isin)
        internal
        view
        returns (IAssetRegistry.Security memory)
    {
        return IAssetRegistry.Security({
            token: token,
            ticker: ticker,
            isin: isin,
            custodian: custodian,
            decimals: 18,
            listing: IAssetRegistry.Listing.Active
        });
    }

    function test_list_storesCanonicalRecord() public {
        vm.prank(owner);
        bytes32 id = registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));

        IAssetRegistry.Security memory stored = registry.securityOf(id);
        assertEq(stored.token, address(apple));
        assertEq(stored.ticker, bytes12("AAPL"));
        assertEq(stored.custodian, custodian);
        assertTrue(registry.isSettleable(id));
        assertEq(registry.idOfToken(address(apple)), id);
        assertEq(registry.count(), 1);
    }

}
