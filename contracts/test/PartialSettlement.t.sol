// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SettlementEngine} from "../src/SettlementEngine.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";
import {ISettlementEngine} from "../src/interfaces/ISettlementEngine.sol";
import {IAssetRegistry} from "../src/interfaces/IAssetRegistry.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PartialSettlementTest is Test {
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

        equity.mint(seller, 10_000e18);
        cash.mint(buyer, 5_000_000e6);

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

    function _affirmed() internal returns (bytes32 id) {
        vm.prank(venue);
        id = engine.affirm(_instruction());
    }

    function test_partial_movesOnlyTheFilledAmount() public {
        bytes32 id = _affirmed();

        engine.settlePartial(id, 100e18);

        assertEq(equity.balanceOf(buyer), 100e18, "buyer receives the filled quantity");
        assertEq(cash.balanceOf(seller), 20_500e6, "seller receives the pro rata cash");

        (uint256 filledQuantity, uint256 filledConsideration, uint256 remaining) = engine.fillOf(id);
        assertEq(filledQuantity, 100e18);
        assertEq(filledConsideration, 20_500e6);
        assertEq(remaining, 300e18);
    }

    /// @dev The instruction stays open until the last unit is delivered.
    function test_partial_staysAffirmedUntilClosed() public {
        bytes32 id = _affirmed();

        engine.settlePartial(id, 399e18);

        (, ISettlementEngine.Status status) = engine.instructionOf(id);
        assertEq(uint8(status), uint8(ISettlementEngine.Status.Affirmed), "one unit still outstanding");
        assertEq(engine.settledCount(), 0, "the counter tracks closed instructions");
    }

    function test_partial_closesOnTheFinalFill() public {
        bytes32 id = _affirmed();

        engine.settlePartial(id, 250e18);
        engine.settlePartial(id, 150e18);

        (, ISettlementEngine.Status status) = engine.instructionOf(id);
        assertEq(uint8(status), uint8(ISettlementEngine.Status.Settled));
        assertEq(engine.settledCount(), 1);

        assertEq(equity.balanceOf(buyer), 400e18, "full quantity delivered");
        assertEq(cash.balanceOf(seller), 82_000e6, "full consideration paid");
    }

    /// @dev The property that makes slicing safe: however an instruction is broken up,
    ///      the parties end up exactly where a single settlement would have left them.
    function test_partial_sumsToTheWholeDespiteRounding() public {
        ISettlementEngine.Instruction memory ins = _instruction();
        ins.quantity = 3e18;
        ins.consideration = 1_000_000; // 1 USDC, which does not divide by three

        vm.prank(venue);
        bytes32 id = engine.affirm(ins);

        engine.settlePartial(id, 1e18);
        engine.settlePartial(id, 1e18);
        engine.settlePartial(id, 1e18);

        assertEq(equity.balanceOf(buyer), 3e18, "every unit delivered");
        assertEq(cash.balanceOf(seller), 1_000_000, "not a single unit of cash lost to rounding");
    }

    function test_partial_revertsWhenAskingForMoreThanRemains() public {
        bytes32 id = _affirmed();
        engine.settlePartial(id, 300e18);

        vm.expectRevert(
            abi.encodeWithSelector(ISettlementEngine.ExceedsRemaining.selector, id, 200e18, 100e18)
        );
        engine.settlePartial(id, 200e18);
    }

    function test_partial_revertsOnZeroQuantity() public {
        bytes32 id = _affirmed();

        vm.expectRevert(ISettlementEngine.ZeroQuantity.selector);
        engine.settlePartial(id, 0);
    }

    function test_partial_revertsOnceClosed() public {
        bytes32 id = _affirmed();
        engine.settlePartial(id, 400e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISettlementEngine.NotAffirmed.selector, id, ISettlementEngine.Status.Settled
            )
        );
        engine.settlePartial(id, 1e18);
    }

    /// @dev A fill is as atomic as a full settlement: a failing cash leg leaves the
    ///      security leg where it was and the fill counters untouched.
    function test_partial_revertsBothLegsWhenCashFails() public {
        bytes32 id = _affirmed();
        engine.settlePartial(id, 100e18);

        vm.prank(buyer);
        cash.approve(address(engine), 0);

        vm.expectRevert();
        engine.settlePartial(id, 100e18);

        assertEq(equity.balanceOf(buyer), 100e18, "the failed fill moved nothing");

        (uint256 filledQuantity,, uint256 remaining) = engine.fillOf(id);
        assertEq(filledQuantity, 100e18, "fill counters unchanged");
        assertEq(remaining, 300e18);
    }

    function test_partial_stopsWhenTheSecurityIsHalted() public {
        bytes32 id = _affirmed();
        engine.settlePartial(id, 100e18);

        vm.prank(owner);
        registry.halt(security, "corporate action");

        vm.expectRevert(abi.encodeWithSelector(ISettlementEngine.SecurityNotListed.selector, security));
        engine.settlePartial(id, 100e18);
    }

    function test_partial_stopsAfterTheDeadline() public {
        ISettlementEngine.Instruction memory ins = _instruction();
        bytes32 id = _affirmed();

        engine.settlePartial(id, 100e18);
        vm.warp(ins.deadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ISettlementEngine.InstructionExpired.selector, id, ins.deadline)
        );
        engine.settlePartial(id, 100e18);
    }

    function test_settle_closesAnInstructionThatWasPartiallyFilled() public {
        bytes32 id = _affirmed();
        engine.settlePartial(id, 120e18);

        engine.settle(id);

        assertEq(equity.balanceOf(buyer), 400e18, "settle finishes the outstanding amount");
        assertEq(cash.balanceOf(seller), 82_000e6);

        (, ISettlementEngine.Status status) = engine.instructionOf(id);
        assertEq(uint8(status), uint8(ISettlementEngine.Status.Settled));
    }

    /// @dev Any slicing at all produces the same outcome as settling in one call.
    function testFuzz_partial_anySlicingMatchesOneSettlement(uint96 first, uint96 second) public {
        ISettlementEngine.Instruction memory ins = _instruction();

        uint256 a = bound(first, 1, ins.quantity - 2);
        uint256 b = bound(second, 1, ins.quantity - a - 1);

        vm.prank(venue);
        bytes32 id = engine.affirm(ins);

        engine.settlePartial(id, a);
        engine.settlePartial(id, b);
        engine.settle(id);

        assertEq(equity.balanceOf(buyer), ins.quantity, "quantity conserved across fills");
        assertEq(cash.balanceOf(seller), ins.consideration, "consideration conserved across fills");

        (uint256 filledQuantity, uint256 filledConsideration, uint256 remaining) = engine.fillOf(id);
        assertEq(filledQuantity, ins.quantity);
        assertEq(filledConsideration, ins.consideration);
        assertEq(remaining, 0);
    }
}
