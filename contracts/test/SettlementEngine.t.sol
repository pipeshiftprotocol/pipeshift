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

        assertEq(equity.balanceOf(buyer), 400e18, "security leg");
        assertEq(cash.balanceOf(seller), 82_000e6, "cash leg");
        assertEq(equity.balanceOf(seller), 600e18, "seller remainder");
        assertEq(engine.settledCount(), 1, "settled counter");

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

        assertEq(equity.balanceOf(seller), 1_000e18, "security must not move");
        assertEq(equity.balanceOf(buyer), 0, "buyer must receive nothing");

        (, ISettlementEngine.Status status) = engine.instructionOf(id);
        assertEq(uint8(status), uint8(ISettlementEngine.Status.Affirmed), "status must not advance");
    }

    function test_settle_revertsOnSecondSettlement() public {
        vm.prank(venue);
        bytes32 id = engine.affirm(_instruction());
        engine.settle(id);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISettlementEngine.NotAffirmed.selector, id, ISettlementEngine.Status.Settled
            )
        );
        engine.settle(id);
    }

    function test_settle_revertsAfterDeadline() public {
        ISettlementEngine.Instruction memory ins = _instruction();

        vm.prank(venue);
        bytes32 id = engine.affirm(ins);

        vm.warp(ins.deadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ISettlementEngine.InstructionExpired.selector, id, ins.deadline)
        );
        engine.settle(id);
    }

    function test_settle_revertsWhenSecurityHalted() public {
        vm.prank(venue);
        bytes32 id = engine.affirm(_instruction());

        vm.prank(owner);
        registry.halt(security, "corporate action");

        vm.expectRevert(abi.encodeWithSelector(ISettlementEngine.SecurityNotListed.selector, security));
        engine.settle(id);
    }

    function test_affirm_revertsForUnregisteredVenue() public {
        address rogue = address(0xBAD);
        vm.prank(rogue);
        vm.expectRevert(abi.encodeWithSelector(ISettlementEngine.NotAVenue.selector, rogue));
        engine.affirm(_instruction());
    }

    function test_affirm_revertsOnDuplicate() public {
        vm.startPrank(venue);
        bytes32 id = engine.affirm(_instruction());

        vm.expectRevert(abi.encodeWithSelector(ISettlementEngine.AlreadyAffirmed.selector, id));
        engine.affirm(_instruction());
        vm.stopPrank();
    }

    function test_affirm_revertsOnSelfTrade() public {
        ISettlementEngine.Instruction memory ins = _instruction();
        ins.buyer = seller;

        vm.prank(venue);
        vm.expectRevert(abi.encodeWithSelector(ISettlementEngine.SelfTrade.selector, seller));
        engine.affirm(ins);
    }

    function test_affirm_revertsOnUnacceptedCash() public {
        MockERC20 other = new MockERC20("Other", "OTH", 6);
        ISettlementEngine.Instruction memory ins = _instruction();
        ins.cash = address(other);

        vm.prank(venue);
        vm.expectRevert(abi.encodeWithSelector(ISettlementEngine.CashNotAccepted.selector, address(other)));
        engine.affirm(ins);
    }

    function test_cancel_byPartyBlocksSettlement() public {
        vm.prank(venue);
        bytes32 id = engine.affirm(_instruction());

        vm.prank(seller);
        engine.cancel(id);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISettlementEngine.NotAffirmed.selector, id, ISettlementEngine.Status.Cancelled
            )
        );
        engine.settle(id);
    }

    function test_settleBatch_isAllOrNothing() public {
        ISettlementEngine.Instruction memory first = _instruction();
        ISettlementEngine.Instruction memory second = _instruction();
        second.quantity = 5_000e18; // more than the seller holds

        vm.startPrank(venue);
        bytes32 idFirst = engine.affirm(first);
        bytes32 idSecond = engine.affirm(second);
        vm.stopPrank();

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = idFirst;
        ids[1] = idSecond;

        vm.expectRevert();
        engine.settleBatch(ids);

        assertEq(equity.balanceOf(buyer), 0, "no leg of the batch may land");
        assertEq(engine.settledCount(), 0, "counter untouched");
    }

    function test_settle_toleratesTokensThatReturnNothing() public {
        NoReturnERC20 quiet = new NoReturnERC20();
        quiet.mint(seller, 100e18);

        vm.prank(owner);
        bytes32 quietId = registry.list(
            IAssetRegistry.Security({
                token: address(quiet),
                ticker: bytes12("TSLA"),
                isin: bytes12("US88160R1014"),
                custodian: custodian,
                decimals: 18,
                listing: IAssetRegistry.Listing.Active
            })
        );

        vm.prank(seller);
        quiet.approve(address(engine), type(uint256).max);

        ISettlementEngine.Instruction memory ins = _instruction();
        ins.security = quietId;
        ins.quantity = 100e18;

        vm.prank(venue);
        bytes32 id = engine.affirm(ins);
        engine.settle(id);

        assertEq(quiet.balanceOf(buyer), 100e18, "no-return token must settle");
    }

    function test_idOf_isDeterministic() public view {
        ISettlementEngine.Instruction memory ins = _instruction();
        assertEq(engine.idOf(ins), engine.idOf(ins));
    }

}
