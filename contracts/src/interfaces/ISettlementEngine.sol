// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISettlementEngine
/// @notice Atomic delivery-versus-payment settlement for tokenized equities.
/// @dev A settlement either moves both legs or neither. There is no state in
///      which the security leg has moved and the cash leg has not.
interface ISettlementEngine {
    /// @notice Lifecycle of a settlement instruction.
    enum Status {
        None,
        Affirmed,
        Settled,
        Cancelled,
        Expired
    }

    /// @notice A matched trade submitted by a venue for settlement.
    /// @param security Canonical registry id of the tokenized equity.
    /// @param cash Address of the cash token used for the payment leg.
    /// @param seller Party delivering the security leg.
    /// @param buyer Party delivering the cash leg.
    /// @param quantity Amount of the security leg, in security decimals.
    /// @param consideration Amount of the cash leg, in cash decimals.
    /// @param deadline Unix timestamp after which the instruction expires.
    /// @param venue Venue that matched the trade and submitted the instruction.
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
    event InstructionFilled(
        bytes32 indexed id, uint256 quantity, uint256 consideration, uint256 remainingQuantity
    );
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
    error ExceedsRemaining(bytes32 id, uint256 requested, uint256 remaining);

    /// @notice Registers a matched trade for settlement.
    /// @dev Only a registered venue may affirm. Affirming does not move value.
    /// @return id Deterministic identifier of the instruction.
    function affirm(Instruction calldata instruction) external returns (bytes32 id);

    /// @notice Settles an affirmed instruction, moving both legs atomically.
    /// @dev Callable by anyone. Both parties must have approved this contract.
    function settle(bytes32 id) external;

    /// @notice Settles part of an affirmed instruction.
    /// @dev Inventory arrives late and in pieces, so an instruction can be closed over
    ///      several fills. Each fill is itself atomic across both legs, and the fill that
    ///      closes the instruction takes the remaining consideration rather than a rounded
    ///      share, so slicing an instruction never changes what the parties end up with.
    function settlePartial(bytes32 id, uint256 quantity) external;

    /// @notice Returns how much of an instruction has been delivered so far.
    function fillOf(bytes32 id)
        external
        view
        returns (uint256 filledQuantity, uint256 filledConsideration, uint256 remainingQuantity);

    /// @notice Settles a batch of affirmed instructions.
    /// @dev Reverts if any instruction in the batch fails, so a batch is all or nothing.
    function settleBatch(bytes32[] calldata ids) external;

    /// @notice Cancels an affirmed instruction before settlement.
    /// @dev Callable by the submitting venue or by either party to the trade.
    function cancel(bytes32 id) external;

    /// @notice Returns the stored instruction and its current status.
    function instructionOf(bytes32 id) external view returns (Instruction memory, Status);

    /// @notice Computes the deterministic id of an instruction without storing it.
    function idOf(Instruction calldata instruction) external pure returns (bytes32);
}
