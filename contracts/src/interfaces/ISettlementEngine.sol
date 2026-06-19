// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISettlementEngine {
    enum Status {
        None,
        Affirmed,
        Settled,
        Cancelled,
        Expired
    }

    struct Instruction {
        bytes32 security;
        address cash;
        address seller;
        address buyer;
        uint256 quantity;
        uint256 consideration;
        uint64 deadline;
        address venue;
    }

    event InstructionAffirmed(bytes32 indexed id, address indexed venue, bytes32 indexed security);
    event InstructionSettled(bytes32 indexed id, address indexed seller, address indexed buyer);
    event InstructionCancelled(bytes32 indexed id, address indexed by);
    event VenueRegistered(address indexed venue);
    event VenueRemoved(address indexed venue);

    error NotAVenue(address caller);
    error UnknownInstruction(bytes32 id);
    error AlreadyAffirmed(bytes32 id);
    error NotAffirmed(bytes32 id, Status status);
    error InstructionExpired(bytes32 id, uint64 deadline);
    error DeadlineInPast(uint64 deadline);
    error ZeroQuantity();
    error ZeroConsideration();
    error SecurityNotListed(bytes32 security);
    error CashNotAccepted(address cash);
    error SelfTrade(address party);

    function affirm(Instruction calldata instruction) external returns (bytes32 id);

    function settle(bytes32 id) external;

    function settleBatch(bytes32[] calldata ids) external;

    function cancel(bytes32 id) external;

    function instructionOf(bytes32 id) external view returns (Instruction memory, Status);

    function idOf(Instruction calldata instruction) external pure returns (bytes32);
}
