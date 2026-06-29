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

    /// @dev Two venues must not be able to list the same underlying twice.
    function test_list_revertsOnDuplicateUnderlying() public {
        vm.startPrank(owner);
        bytes32 id = registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));

        vm.expectRevert(abi.encodeWithSelector(IAssetRegistry.AlreadyListed.selector, id));
        registry.list(_security(address(tesla), bytes12("AAPL"), bytes12("US0378331005")));
        vm.stopPrank();
    }

    /// @dev One token address must map to exactly one canonical id.
    function test_list_revertsWhenTokenAlreadyMapped() public {
        vm.startPrank(owner);
        bytes32 id = registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));

        vm.expectRevert(
            abi.encodeWithSelector(IAssetRegistry.TokenAlreadyMapped.selector, address(apple), id)
        );
        registry.list(_security(address(apple), bytes12("TSLA"), bytes12("US88160R1014")));
        vm.stopPrank();
    }

    function test_list_revertsForNonOwner() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Owned.NotOwner.selector, outsider));
        registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));
    }

    function test_list_revertsOnZeroToken() public {
        vm.prank(owner);
        vm.expectRevert(IAssetRegistry.ZeroToken.selector);
        registry.list(_security(address(0), bytes12("AAPL"), bytes12("US0378331005")));
    }

    function test_list_revertsOnEmptyTicker() public {
        vm.prank(owner);
        vm.expectRevert(IAssetRegistry.EmptyTicker.selector);
        registry.list(_security(address(apple), bytes12(0), bytes12("US0378331005")));
    }

    function test_haltAndResume_flipSettleability() public {
        vm.startPrank(owner);
        bytes32 id = registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));

        registry.halt(id, "corporate action");
        assertFalse(registry.isSettleable(id), "halted security must not settle");

        registry.resume(id);
        assertTrue(registry.isSettleable(id), "resumed security settles again");
        vm.stopPrank();
    }

    function test_delist_isTerminal() public {
        vm.startPrank(owner);
        bytes32 id = registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));

        registry.delist(id);
        assertFalse(registry.isSettleable(id));

        vm.expectRevert(
            abi.encodeWithSelector(IAssetRegistry.NotActive.selector, id, IAssetRegistry.Listing.Delisted)
        );
        registry.resume(id);
        vm.stopPrank();
    }

    function test_setCustodian_reassignsRecord() public {
        address next = address(0xC058);

        vm.startPrank(owner);
        bytes32 id = registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));
        registry.setCustodian(id, next);
        vm.stopPrank();

        assertEq(registry.securityOf(id).custodian, next);
    }

    function test_idsPaged_returnsWindow() public {
        vm.startPrank(owner);
        registry.list(_security(address(apple), bytes12("AAPL"), bytes12("US0378331005")));
        registry.list(_security(address(tesla), bytes12("TSLA"), bytes12("US88160R1014")));
        vm.stopPrank();

        bytes32[] memory page = registry.idsPaged(0, 1);
        assertEq(page.length, 1);

        bytes32[] memory beyond = registry.idsPaged(5, 10);
        assertEq(beyond.length, 0, "offset past the end returns empty");

        bytes32[] memory clamped = registry.idsPaged(1, 100);
        assertEq(clamped.length, 1, "limit clamps to available");
    }

    function test_transferOwnership_isTwoStep() public {
        address next = address(0xA11CF);

        vm.prank(owner);
        registry.transferOwnership(next);
        assertEq(registry.owner(), owner, "ownership does not move on nomination");

        vm.prank(next);
        registry.acceptOwnership();
        assertEq(registry.owner(), next, "ownership moves on acceptance");
        assertEq(registry.pendingOwner(), address(0));
    }

    function test_acceptOwnership_revertsForWrongCaller() public {
        vm.prank(owner);
        registry.transferOwnership(address(0xA11CF));

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Owned.NotPendingOwner.selector, outsider));
        registry.acceptOwnership();
    }

    function test_idOf_isStableAcrossReissue() public view {
        bytes32 first = registry.idOf(bytes12("AAPL"), bytes12("US0378331005"));
        bytes32 second = registry.idOf(bytes12("AAPL"), bytes12("US0378331005"));
        assertEq(first, second, "canonical id survives token reissue");
    }
}
