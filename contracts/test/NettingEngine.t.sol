// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NettingEngine} from "../src/NettingEngine.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract NettingEngineTest is Test {
    NettingEngine internal netting;
    AssetRegistry internal registry;
    MockERC20 internal equity;
    MockERC20 internal cash;

    address internal owner = address(0xA11CE);
    address internal venue = address(0xFEE);
    address internal custodian = address(0xC057);

    address internal deskA = address(0xDA);
    address internal deskB = address(0xDB);
    address internal deskC = address(0xDC);

    bytes32 internal security;

    function setUp() public {
        registry = new AssetRegistry(owner);
        netting = new NettingEngine(owner, IAssetRegistry(address(registry)));

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
        netting.registerVenue(venue);
        vm.stopPrank();

        address[3] memory desks = [deskA, deskB, deskC];
        for (uint256 i; i < desks.length; ++i) {
            equity.mint(desks[i], 10_000e18);
            cash.mint(desks[i], 5_000_000e6);

            vm.startPrank(desks[i]);
            equity.approve(address(netting), type(uint256).max);
            cash.approve(address(netting), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// @dev Three desks, a session that nets to zero on both legs.
    function _balancedSession() internal view returns (NettingEngine.Session memory session) {
        NettingEngine.Leg[] memory legs = new NettingEngine.Leg[](3);
        legs[0] = NettingEngine.Leg({party: deskA, quantityDelta: 600e18, cashDelta: -123_000e6});
        legs[1] = NettingEngine.Leg({party: deskB, quantityDelta: -400e18, cashDelta: 82_000e6});
        legs[2] = NettingEngine.Leg({party: deskC, quantityDelta: -200e18, cashDelta: 41_000e6});

        session = NettingEngine.Session({security: security, cash: address(cash), legs: legs});
    }

    function test_settleSession_appliesNetPositions() public {
        vm.prank(venue);
        netting.settleSession(_balancedSession(), 12_000);

        assertEq(equity.balanceOf(deskA), 10_600e18, "deskA receives net long");
        assertEq(equity.balanceOf(deskB), 9_600e18, "deskB delivers net short");
        assertEq(equity.balanceOf(deskC), 9_800e18, "deskC delivers net short");

        assertEq(cash.balanceOf(deskA), 4_877_000e6, "deskA pays net cash");
        assertEq(cash.balanceOf(deskB), 5_082_000e6, "deskB receives net cash");
        assertEq(cash.balanceOf(deskC), 5_041_000e6, "deskC receives net cash");

        assertEq(netting.sessionCount(), 1);
        assertEq(netting.grossTradesNetted(), 12_000);
    }

    /// @dev The engine must not be left holding anything once a session closes.
    function test_settleSession_leavesNoResidualInEngine() public {
        vm.prank(venue);
        netting.settleSession(_balancedSession(), 12_000);

        assertEq(equity.balanceOf(address(netting)), 0, "no security dust");
        assertEq(cash.balanceOf(address(netting)), 0, "no cash dust");
    }

    function test_settleSession_revertsWhenQuantityDoesNotNet() public {
        NettingEngine.Session memory session = _balancedSession();
        session.legs[0].quantityDelta = 601e18;

        vm.prank(venue);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.QuantityDoesNotNet.selector, int256(1e18)));
        netting.settleSession(session, 12_000);
    }

    function test_settleSession_revertsWhenCashDoesNotNet() public {
        NettingEngine.Session memory session = _balancedSession();
        session.legs[1].cashDelta = 82_001e6;

        vm.prank(venue);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.CashDoesNotNet.selector, int256(1e6)));
        netting.settleSession(session, 12_000);
    }

    function test_settleSession_revertsOnDuplicateParty() public {
        NettingEngine.Leg[] memory legs = new NettingEngine.Leg[](2);
        legs[0] = NettingEngine.Leg({party: deskA, quantityDelta: 100e18, cashDelta: -100e6});
        legs[1] = NettingEngine.Leg({party: deskA, quantityDelta: -100e18, cashDelta: 100e6});

        NettingEngine.Session memory session =
            NettingEngine.Session({security: security, cash: address(cash), legs: legs});

        vm.prank(venue);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.DuplicateParty.selector, deskA));
        netting.settleSession(session, 2);
    }

    function test_settleSession_revertsForUnregisteredVenue() public {
        address rogue = address(0xBAD);
        vm.prank(rogue);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.NotAVenue.selector, rogue));
        netting.settleSession(_balancedSession(), 12_000);
    }

    function test_settleSession_revertsWhenSecurityHalted() public {
        vm.prank(owner);
        registry.halt(security, "corporate action");

        vm.prank(venue);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.SecurityNotListed.selector, security));
        netting.settleSession(_balancedSession(), 12_000);
    }

    function test_settleSession_revertsOnEmptySession() public {
        NettingEngine.Session memory session = NettingEngine.Session({
            security: security, cash: address(cash), legs: new NettingEngine.Leg[](0)
        });

        vm.prank(venue);
        vm.expectRevert(NettingEngine.NoLegs.selector);
        netting.settleSession(session, 0);
    }

    /// @dev A desk that nets flat should not move value at all.
    function test_settleSession_skipsPartiesThatNetFlat() public {
        NettingEngine.Leg[] memory legs = new NettingEngine.Leg[](3);
        legs[0] = NettingEngine.Leg({party: deskA, quantityDelta: 500e18, cashDelta: -100_000e6});
        legs[1] = NettingEngine.Leg({party: deskB, quantityDelta: -500e18, cashDelta: 100_000e6});
        legs[2] = NettingEngine.Leg({party: deskC, quantityDelta: 0, cashDelta: 0});

        NettingEngine.Session memory session =
            NettingEngine.Session({security: security, cash: address(cash), legs: legs});

        vm.prank(venue);
        netting.settleSession(session, 900);

        assertEq(equity.balanceOf(deskC), 10_000e18, "flat desk untouched");
        assertEq(cash.balanceOf(deskC), 5_000_000e6, "flat desk untouched");
    }

}
