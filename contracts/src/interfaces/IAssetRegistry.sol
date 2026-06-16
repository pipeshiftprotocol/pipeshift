// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAssetRegistry {
    enum Listing {
        None,
        Active,
        Halted,
        Delisted
    }

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

    function list(Security calldata security) external returns (bytes32 id);

    function halt(bytes32 id, string calldata reason) external;

    function resume(bytes32 id) external;

    function delist(bytes32 id) external;

    function setCustodian(bytes32 id, address custodian) external;

    function securityOf(bytes32 id) external view returns (Security memory);

    function idOfToken(address token) external view returns (bytes32);

    function isSettleable(bytes32 id) external view returns (bool);

    function count() external view returns (uint256);
}
