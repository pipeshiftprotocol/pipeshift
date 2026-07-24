// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAssetRegistry
/// @notice One canonical record per tokenized equity, shared by every venue.
/// @dev Without a shared registry, two venues can list the same underlying under
///      different token addresses and settle against each other by accident.
///      The registry makes the mapping from token to underlying explicit.
interface IAssetRegistry {
    /// @notice Whether a listed security can currently be settled.
    enum Listing {
        None,
        Active,
        Halted,
        Delisted
    }

    /// @notice Canonical record for one tokenized equity.
    /// @param token Address of the tokenized equity on Robinhood Chain.
    /// @param ticker Underlying ticker, for example AAPL.
    /// @param isin ISIN of the underlying instrument.
    /// @param custodian Party attesting that the underlying is held.
    /// @param decimals Decimals of the tokenized representation.
    /// @param listing Current listing state.
    struct Security {
        address token;
        bytes12 ticker;
        bytes12 isin;
        address custodian;
        uint8 decimals;
        Listing listing;
    }

    event SecurityListed(bytes32 indexed id, address indexed token, bytes12 ticker);
    event SecurityHalted(bytes32 indexed id, string reason);
    event SecurityResumed(bytes32 indexed id);
    event SecurityDelisted(bytes32 indexed id);
    event CustodianChanged(bytes32 indexed id, address indexed from, address indexed to);

    error AlreadyListed(bytes32 id);
    error NotListed(bytes32 id);
    error NotActive(bytes32 id, Listing listing);
    error TokenAlreadyMapped(address token, bytes32 id);
    error ZeroToken();
    error ZeroCustodian();
    error EmptyTicker();

    /// @notice Lists a tokenized equity under a canonical id.
    function list(Security calldata security) external returns (bytes32 id);

    /// @notice Halts settlement for a security without delisting it.
    function halt(bytes32 id, string calldata reason) external;

    /// @notice Resumes settlement for a halted security.
    function resume(bytes32 id) external;

    /// @notice Permanently delists a security.
    function delist(bytes32 id) external;

    /// @notice Reassigns the custodian of record.
    function setCustodian(bytes32 id, address custodian) external;

    /// @notice Returns the canonical record for an id.
    function securityOf(bytes32 id) external view returns (Security memory);

    /// @notice Returns the canonical id for a token address.
    function idOfToken(address token) external view returns (bytes32);

    /// @notice Whether a security exists and is currently settleable.
    function isSettleable(bytes32 id) external view returns (bool);

    /// @notice Number of securities ever listed.
    function count() external view returns (uint256);
}
