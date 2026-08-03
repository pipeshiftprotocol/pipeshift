// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISettlementEngine} from "./interfaces/ISettlementEngine.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Owned} from "./libraries/Owned.sol";
import {SafeTransfer} from "./libraries/SafeTransfer.sol";

/// @title SettlementEngine
/// @notice Atomic delivery-versus-payment for matched trades in tokenized equities.
/// @dev The engine never holds positions between calls. Both legs move inside one
///      transaction, so a failed cash leg reverts the security leg with it. Venues
///      match and affirm, the engine settles.
contract SettlementEngine is ISettlementEngine, Owned {
    using SafeTransfer for IERC20;

    IAssetRegistry public immutable registry;

    mapping(bytes32 => Instruction) private _instructions;
    mapping(bytes32 => Status) private _status;

    /// @dev How much of each leg an instruction has already delivered. Both are needed:
    ///      the cash filled is not derivable from the quantity filled, because the final
    ///      fill takes the remainder rather than a rounded share.
    mapping(bytes32 => uint256) private _filledQuantity;
    mapping(bytes32 => uint256) private _filledConsideration;
    mapping(address => bool) public isVenue;
    mapping(address => bool) public isCashAccepted;

    /// @notice Number of instructions settled over the life of the contract.
    uint256 public settledCount;

    constructor(address owner_, IAssetRegistry registry_) Owned(owner_) {
        registry = registry_;
    }

    modifier onlyVenue() {
        if (!isVenue[msg.sender]) revert NotAVenue(msg.sender);
        _;
    }

    /// @notice Adds a venue permitted to affirm instructions.
    function registerVenue(address venue) external onlyOwner {
        isVenue[venue] = true;
        emit VenueRegistered(venue);
    }

    /// @notice Removes a venue. Instructions it already affirmed stay settleable.
    function removeVenue(address venue) external onlyOwner {
        isVenue[venue] = false;
        emit VenueRemoved(venue);
    }

    /// @notice Marks a token as acceptable for the cash leg.
    function setCashAccepted(address cash, bool accepted) external onlyOwner {
        isCashAccepted[cash] = accepted;
    }

    /// @inheritdoc ISettlementEngine
    function affirm(Instruction calldata instruction) external onlyVenue returns (bytes32 id) {
        if (instruction.quantity == 0) revert ZeroQuantity();
        if (instruction.consideration == 0) revert ZeroConsideration();
        if (instruction.deadline <= block.timestamp) revert DeadlineInPast(instruction.deadline);
        if (instruction.seller == instruction.buyer) revert SelfTrade(instruction.seller);
        if (!registry.isSettleable(instruction.security)) revert SecurityNotListed(instruction.security);
        if (!isCashAccepted[instruction.cash]) revert CashNotAccepted(instruction.cash);

        id = idOf(instruction);
        if (_status[id] != Status.None) revert AlreadyAffirmed(id);

        _instructions[id] = instruction;
        _status[id] = Status.Affirmed;

        emit InstructionAffirmed(id, msg.sender, instruction.security);
    }

    /// @inheritdoc ISettlementEngine
    function settle(bytes32 id) external {
        _settle(id);
    }

    /// @inheritdoc ISettlementEngine
    function settleBatch(bytes32[] calldata ids) external {
        uint256 length = ids.length;
        for (uint256 i; i < length; ++i) {
            _settle(ids[i]);
        }
    }

    /// @inheritdoc ISettlementEngine
    function cancel(bytes32 id) external {
        Status status = _status[id];
        if (status == Status.None) revert UnknownInstruction(id);
        if (status != Status.Affirmed) revert NotAffirmed(id, status);

        Instruction memory ins = _instructions[id];
        bool permitted = msg.sender == ins.venue || msg.sender == ins.seller || msg.sender == ins.buyer;
        if (!permitted) revert NotAVenue(msg.sender);

        _status[id] = Status.Cancelled;
        emit InstructionCancelled(id, msg.sender);
    }

    /// @inheritdoc ISettlementEngine
    function instructionOf(bytes32 id) external view returns (Instruction memory, Status) {
        return (_instructions[id], _status[id]);
    }

    /// @inheritdoc ISettlementEngine
    function fillOf(bytes32 id)
        external
        view
        returns (uint256 filledQuantity, uint256 filledConsideration, uint256 remainingQuantity)
    {
        filledQuantity = _filledQuantity[id];
        filledConsideration = _filledConsideration[id];
        remainingQuantity = _instructions[id].quantity - filledQuantity;
    }

    /// @inheritdoc ISettlementEngine
    function idOf(Instruction calldata instruction) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                instruction.security,
                instruction.cash,
                instruction.seller,
                instruction.buyer,
                instruction.quantity,
                instruction.consideration,
                instruction.deadline,
                instruction.venue
            )
        );
    }

    /// @inheritdoc ISettlementEngine
    function settlePartial(bytes32 id, uint256 quantity) external {
        if (quantity == 0) revert ZeroQuantity();
        _fill(id, quantity);
    }

    /// @dev Settles the whole outstanding amount, which for an untouched instruction is
    ///      the entire quantity. Expressing it through the same path as a partial fill
    ///      means there is one settlement routine to reason about rather than two.
    function _settle(bytes32 id) private {
        uint256 remaining = _instructions[id].quantity - _filledQuantity[id];
        _fill(id, remaining);
    }

    /// @dev Moves the security leg first, then the cash leg. Either both land or the whole
    ///      call reverts, which is the only property that matters here.
    ///
    ///      The cash owed for a partial fill is its pro rata share, rounded down, except
    ///      for the fill that closes the instruction: that one takes whatever consideration
    ///      is left. Rounding therefore cannot leak value in either direction, however the
    ///      caller chooses to slice the instruction up.
    function _fill(bytes32 id, uint256 quantity) private {
        Status status = _status[id];
        if (status == Status.None) revert UnknownInstruction(id);
        if (status != Status.Affirmed) revert NotAffirmed(id, status);

        Instruction memory ins = _instructions[id];
        if (block.timestamp > ins.deadline) revert InstructionExpired(id, ins.deadline);
        if (!registry.isSettleable(ins.security)) revert SecurityNotListed(ins.security);

        uint256 filled = _filledQuantity[id];
        uint256 remaining = ins.quantity - filled;
        if (quantity > remaining) revert ExceedsRemaining(id, quantity, remaining);

        uint256 consideration;
        bool closes = quantity == remaining;

        if (closes) {
            consideration = ins.consideration - _filledConsideration[id];
            _status[id] = Status.Settled;
            unchecked {
                ++settledCount;
            }
        } else {
            consideration = (ins.consideration * quantity) / ins.quantity;
        }

        _filledQuantity[id] = filled + quantity;
        _filledConsideration[id] += consideration;

        address securityToken = registry.securityOf(ins.security).token;

        IERC20(securityToken).safeTransferFrom(ins.seller, ins.buyer, quantity);
        IERC20(ins.cash).safeTransferFrom(ins.buyer, ins.seller, consideration);

        emit InstructionFilled(id, quantity, consideration, remaining - quantity);

        if (closes) emit InstructionSettled(id, ins.seller, ins.buyer);
    }
}
