// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {NettingEngine} from "../src/NettingEngine.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AggregatedNettingTest is Test {
    NettingEngine internal netting;
    AssetRegistry internal registry;
    MockERC20 internal equity;
    MockERC20 internal cash;

    address internal owner = address(0xA11CE);
    address internal venueOne = address(0xFEE1);
    address internal venueTwo = address(0xFEE2);
    address internal outsider = address(0xBAD);
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
        netting.registerVenue(venueOne);
        netting.registerVenue(venueTwo);
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

    function _venues() internal view returns (address[] memory venues) {
        venues = new address[](2);
        venues[0] = venueOne;
        venues[1] = venueTwo;
    }

    /// @dev deskA is long 500 on one venue and short 500 on the other, so the combined
    ///      session leaves it flat and it moves nothing at all.
    function _combined() internal view returns (NettingEngine.Session memory session) {
        NettingEngine.Leg[] memory legs = new NettingEngine.Leg[](2);
        legs[0] = NettingEngine.Leg({party: deskB, quantityDelta: -500e18, cashDelta: 100_000e6});
        legs[1] = NettingEngine.Leg({party: deskC, quantityDelta: 500e18, cashDelta: -100_000e6});

        session = NettingEngine.Session({security: security, cash: address(cash), legs: legs});
    }

    function test_aggregated_settlesTheCombinedSession() public {
        vm.prank(venueOne);
        netting.settleAggregated(_combined(), _venues(), 8_400);

        assertEq(equity.balanceOf(deskA), 10_000e18, "the desk that nets flat across venues moves nothing");
        assertEq(cash.balanceOf(deskA), 5_000_000e6, "and pays nothing");

        assertEq(equity.balanceOf(deskB), 9_500e18);
        assertEq(equity.balanceOf(deskC), 10_500e18);
        assertEq(netting.grossTradesNetted(), 8_400);
    }

    function test_aggregated_recordsTheVenuesItCovers() public {
        vm.recordLogs();

        vm.prank(venueTwo);
        netting.settleAggregated(_combined(), _venues(), 8_400);

        // The venue list is what makes an aggregated session auditable after the fact.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("SessionAggregated(uint256,bytes32,address[])")) {
                found = true;
                assertEq(logs[i].topics[2], security, "event names the security");
            }
        }
        assertTrue(found, "an aggregated session emits its venue list");
    }

    function test_aggregated_requiresEveryVenueToBeRegistered() public {
        address[] memory venues = new address[](2);
        venues[0] = venueOne;
        venues[1] = outsider;

        vm.prank(venueOne);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.VenueNotRegistered.selector, outsider));
        netting.settleAggregated(_combined(), venues, 8_400);
    }

    /// @dev A venue cannot settle a group it does not belong to.
    function test_aggregated_requiresTheCallerToBeInTheGroup() public {
        address[] memory venues = new address[](1);
        venues[0] = venueTwo;

        vm.prank(venueOne);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.NotAVenue.selector, venueOne));
        netting.settleAggregated(_combined(), venues, 8_400);
    }

    function test_aggregated_rejectsAnEmptyVenueList() public {
        vm.prank(venueOne);
        vm.expectRevert(NettingEngine.NoVenues.selector);
        netting.settleAggregated(_combined(), new address[](0), 8_400);
    }

    function test_aggregated_stillRequiresTheSessionToNet() public {
        NettingEngine.Session memory session = _combined();
        session.legs[0].quantityDelta = -499e18;

        vm.prank(venueOne);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.QuantityDoesNotNet.selector, int256(1e18)));
        netting.settleAggregated(session, _venues(), 8_400);
    }

    function test_aggregated_stopsWhenTheSecurityIsHalted() public {
        vm.prank(owner);
        registry.halt(security, "corporate action");

        vm.prank(venueOne);
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.SecurityNotListed.selector, security));
        netting.settleAggregated(_combined(), _venues(), 8_400);
    }

    /// @dev Settling one combined session must leave desks exactly where settling each
    ///      venue separately would have, which is the whole claim behind aggregation.
    function testFuzz_aggregated_matchesSettlingVenuesSeparately(uint96 a, uint96 b) public {
        uint256 first = bound(a, 1e18, 4_000e18);
        uint256 second = bound(b, 1e18, 4_000e18);

        // Cash carries six decimals against the security's eighteen, so the money legs
        // are scaled rather than mirrored. Mirroring them would ask a desk for more USDC
        // than exists.
        uint256 firstCash = first / 1e12;
        uint256 secondCash = second / 1e12;

        // Venue one: deskB delivers `first` to deskA. Venue two: deskA delivers `second`
        // to deskC. Aggregated, deskA only moves the difference.
        NettingEngine.Leg[] memory legs = new NettingEngine.Leg[](3);
        legs[0] = NettingEngine.Leg({
            party: deskA,
            quantityDelta: int256(first) - int256(second),
            cashDelta: -int256(firstCash) + int256(secondCash)
        });
        legs[1] =
            NettingEngine.Leg({party: deskB, quantityDelta: -int256(first), cashDelta: int256(firstCash)});
        legs[2] =
            NettingEngine.Leg({party: deskC, quantityDelta: int256(second), cashDelta: -int256(secondCash)});

        NettingEngine.Session memory session =
            NettingEngine.Session({security: security, cash: address(cash), legs: legs});

        uint256 supplyBefore = equity.totalSupply();

        vm.prank(venueOne);
        netting.settleAggregated(session, _venues(), 100);

        assertEq(equity.totalSupply(), supplyBefore, "supply conserved");
        assertEq(equity.balanceOf(address(netting)), 0, "no residual held");
        assertEq(
            equity.balanceOf(deskA),
            uint256(int256(10_000e18) + int256(first) - int256(second)),
            "deskA moved only the difference between the two venues"
        );
    }
}
