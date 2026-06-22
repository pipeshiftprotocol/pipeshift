// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SettlementEngine} from "../src/SettlementEngine.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {ISettlementEngine} from "../src/interfaces/ISettlementEngine.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {SafeTransfer} from "../src/libraries/SafeTransfer.sol";
import {Owned} from "../src/libraries/Owned.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {NoReturnERC20} from "./mocks/NoReturnERC20.sol";

contract SettlementEngineTest is Test {
    SettlementEngine internal engine;
    AssetRegistry internal registry;
    MockERC20 internal equity;
    MockERC20 internal cash;

    address internal owner = address(0xA11CE);
    address internal venue = address(0xFEE);
    address internal seller = address(0x5E11);
    address internal buyer = address(0xB0B);
    address internal custodian = address(0xC057);

    bytes32 internal security;

    function setUp() public {
        registry = new AssetRegistry(owner);
        engine = new SettlementEngine(owner, IAssetRegistry(address(registry)));

        equity = new MockERC20("Pipeshift Apple", "pAAPL", 18);
        cash = new MockERC20("USD Coin", "USDC", 6);

        vm.startPrank(owner);
        security = registry.list(
            IAssetRegistry.Security({
                token: address(equity),
                ticker: bytes12("AAPL"),
                isin: bytes12("US0378331005"),
                custodian: custodian,
                decimals: 18,
                listing: IAssetRegistry.Listing.Active
            })
        );
        engine.registerVenue(venue);
        engine.setCashAccepted(address(cash), true);
        vm.stopPrank();

        equity.mint(seller, 1_000e18);
        cash.mint(buyer, 500_000e6);

        vm.prank(seller);
        equity.approve(address(engine), type(uint256).max);
        vm.prank(buyer);
        cash.approve(address(engine), type(uint256).max);
    }

    function _instruction() internal view returns (ISettlementEngine.Instruction memory) {
        return ISettlementEngine.Instruction({
            security: security,
            cash: address(cash),
            seller: seller,
            buyer: buyer,
            quantity: 400e18,
            consideration: 82_000e6,
            deadline: uint64(block.timestamp + 1 days),
            venue: venue
        });
    }

    function test_settle_movesBothLegs() public {
        vm.prank(venue);
        bytes32 id = engine.affirm(_instruction());

        engine.settle(id);

        assertEq(equity.balanceOf(buyer), 400e18);
        assertEq(cash.balanceOf(seller), 82_000e6);
        assertEq(equity.balanceOf(seller), 600e18);
        assertEq(engine.settledCount(), 1);

        (, ISettlementEngine.Status status) = engine.instructionOf(id);
        assertEq(uint8(status), uint8(ISettlementEngine.Status.Settled));
    }

    /// @dev The property the whole contract exists for: a failing cash leg must not
    ///      leave the security leg moved.
    function test_settle_revertsWholeTradeWhenCashLegFails() public {
        vm.prank(buyer);
        cash.approve(address(engine), 0);

        vm.prank(venue);
        bytes32 id = engine.affirm(_instruction());

        vm.expectRevert();
        engine.settle(id);

        assertEq(equity.balanceOf(seller), 1_000e18);
        assertEq(equity.balanceOf(buyer), 0);

        (, ISettlementEngine.Status status) = engine.instructionOf(id);
        assertEq(uint8(status), uint8(ISettlementEngine.Status.Affirmed));
    }

}
