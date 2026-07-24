// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {Owned} from "./libraries/Owned.sol";

/// @title AssetRegistry
/// @notice The canonical registry of tokenized equities every venue settles against.
/// @dev Ids are derived from ticker and ISIN rather than from the token address, so a
///      reissued token keeps the same canonical id and history stays continuous.
contract AssetRegistry is IAssetRegistry, Owned {
    mapping(bytes32 => Security) private _securities;
    mapping(address => bytes32) private _idOfToken;

    bytes32[] private _ids;

    constructor(address owner_) Owned(owner_) {}

    /// @inheritdoc IAssetRegistry
    function list(Security calldata security) external onlyOwner returns (bytes32 id) {
        if (security.token == address(0)) revert ZeroToken();
        if (security.custodian == address(0)) revert ZeroCustodian();
        if (security.ticker == bytes12(0)) revert EmptyTicker();

        id = idOf(security.ticker, security.isin);

        if (_securities[id].listing != Listing.None) revert AlreadyListed(id);

        bytes32 mapped = _idOfToken[security.token];
        if (mapped != bytes32(0)) revert TokenAlreadyMapped(security.token, mapped);

        _securities[id] = Security({
            token: security.token,
            ticker: security.ticker,
            isin: security.isin,
            custodian: security.custodian,
            decimals: security.decimals,
            listing: Listing.Active
        });
        _idOfToken[security.token] = id;
        _ids.push(id);

        emit SecurityListed(id, security.token, security.ticker);
    }

    /// @inheritdoc IAssetRegistry
    function halt(bytes32 id, string calldata reason) external onlyOwner {
        Security storage s = _securities[id];
        if (s.listing == Listing.None) revert NotListed(id);
        if (s.listing != Listing.Active) revert NotActive(id, s.listing);

        s.listing = Listing.Halted;
        emit SecurityHalted(id, reason);
    }

    /// @inheritdoc IAssetRegistry
    function resume(bytes32 id) external onlyOwner {
        Security storage s = _securities[id];
        if (s.listing != Listing.Halted) revert NotActive(id, s.listing);

        s.listing = Listing.Active;
        emit SecurityResumed(id);
    }

    /// @inheritdoc IAssetRegistry
    function delist(bytes32 id) external onlyOwner {
        Security storage s = _securities[id];
        if (s.listing == Listing.None) revert NotListed(id);

        s.listing = Listing.Delisted;
        emit SecurityDelisted(id);
    }

    /// @inheritdoc IAssetRegistry
    function setCustodian(bytes32 id, address custodian) external onlyOwner {
        if (custodian == address(0)) revert ZeroCustodian();

        Security storage s = _securities[id];
        if (s.listing == Listing.None) revert NotListed(id);

        address previous = s.custodian;
        s.custodian = custodian;
        emit CustodianChanged(id, previous, custodian);
    }

    /// @inheritdoc IAssetRegistry
    function securityOf(bytes32 id) external view returns (Security memory) {
        return _securities[id];
    }

    /// @inheritdoc IAssetRegistry
    function idOfToken(address token) external view returns (bytes32) {
        return _idOfToken[token];
    }

    /// @inheritdoc IAssetRegistry
    function isSettleable(bytes32 id) external view returns (bool) {
        return _securities[id].listing == Listing.Active;
    }

    /// @inheritdoc IAssetRegistry
    function count() external view returns (uint256) {
        return _ids.length;
    }

    /// @notice Returns a page of listed ids.
    /// @dev Paged because the full list grows without bound.
    function idsPaged(uint256 offset, uint256 limit) external view returns (bytes32[] memory page) {
        uint256 total = _ids.length;
        if (offset >= total) return new bytes32[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        page = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = _ids[i];
        }
    }

    /// @notice Derives the canonical id from ticker and ISIN.
    function idOf(bytes12 ticker, bytes12 isin) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ticker, isin));
    }
}
