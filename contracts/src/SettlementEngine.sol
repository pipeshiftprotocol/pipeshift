// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISettlementEngine} from "./interfaces/ISettlementEngine.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Owned} from "./libraries/Owned.sol";
import {SafeTransfer} from "./libraries/SafeTransfer.sol";

contract SettlementEngine is ISettlementEngine, Owned {
    using SafeTransfer for IERC20;

    IAssetRegistry public immutable registry;

    mapping(bytes32 => Instruction) private _instructions;
    mapping(bytes32 => Status) private _status;
    mapping(address => bool) public isVenue;
    mapping(address => bool) public isCashAccepted;

    uint256 public settledCount;

    constructor(address owner_, IAssetRegistry registry_) Owned(owner_) {
        registry = registry_;
    }

    modifier onlyVenue() {
        if (!isVenue[msg.sender]) revert NotAVenue(msg.sender);
        _;
    }

    function registerVenue(address venue) external onlyOwner {
        isVenue[venue] = true;
        emit VenueRegistered(venue);
    }

    function removeVenue(address venue) external onlyOwner {
        isVenue[venue] = false;
        emit VenueRemoved(venue);
    }

    function setCashAccepted(address cash, bool accepted) external onlyOwner {
        isCashAccepted[cash] = accepted;
    }

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

    function settle(bytes32 id) external {
        _settle(id);
    }

    function settleBatch(bytes32[] calldata ids) external {
        uint256 length = ids.length;
        for (uint256 i; i < length; ++i) {
            _settle(ids[i]);
        }
    }

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

    function instructionOf(bytes32 id) external view returns (Instruction memory, Status) {
        return (_instructions[id], _status[id]);
    }

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

    function _settle(bytes32 id) private {
        Status status = _status[id];
        if (status == Status.None) revert UnknownInstruction(id);
        if (status != Status.Affirmed) revert NotAffirmed(id, status);

        Instruction memory ins = _instructions[id];
        if (block.timestamp > ins.deadline) revert InstructionExpired(id, ins.deadline);
        if (!registry.isSettleable(ins.security)) revert SecurityNotListed(ins.security);

        address securityToken = registry.securityOf(ins.security).token;

        _status[id] = Status.Settled;
        unchecked {
            ++settledCount;
        }

        IERC20(securityToken).safeTransferFrom(ins.seller, ins.buyer, ins.quantity);
        IERC20(ins.cash).safeTransferFrom(ins.buyer, ins.seller, ins.consideration);

        emit InstructionSettled(id, ins.seller, ins.buyer);
    }
}
