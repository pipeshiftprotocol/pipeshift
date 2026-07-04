// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISettlementEngine} from "./interfaces/ISettlementEngine.sol";
import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Owned} from "./libraries/Owned.sol";
import {SafeTransfer} from "./libraries/SafeTransfer.sol";

contract NettingEngine is Owned {
    using SafeTransfer for IERC20;

    struct Leg {
        address party;
        int256 quantityDelta;
        int256 cashDelta;
    }

    struct Session {
        bytes32 security;
        address cash;
        Leg[] legs;
    }

    IAssetRegistry public immutable registry;

    uint256 public sessionCount;

    uint256 public grossTradesNetted;

    mapping(address => bool) public isVenue;

    event SessionSettled(
        uint256 indexed session, bytes32 indexed security, uint256 legs, uint256 grossTrades
    );
    event VenueRegistered(address indexed venue);
    event VenueRemoved(address indexed venue);

    error NotAVenue(address caller);
    error SecurityNotListed(bytes32 security);
    error NoLegs();
    error QuantityDoesNotNet(int256 residual);
    error CashDoesNotNet(int256 residual);
    error DuplicateParty(address party);
    error ZeroParty();

    constructor(address owner_, IAssetRegistry registry_) Owned(owner_) {
        registry = registry_;
    }

    function registerVenue(address venue) external onlyOwner {
        isVenue[venue] = true;
        emit VenueRegistered(venue);
    }

    function removeVenue(address venue) external onlyOwner {
        isVenue[venue] = false;
        emit VenueRemoved(venue);
    }

    function settleSession(Session calldata session, uint256 grossTrades) external {
        if (!isVenue[msg.sender]) revert NotAVenue(msg.sender);

        uint256 count = session.legs.length;
        if (count == 0) revert NoLegs();
        if (!registry.isSettleable(session.security)) revert SecurityNotListed(session.security);

        int256 quantityResidual;
        int256 cashResidual;

        for (uint256 i; i < count; ++i) {
            Leg calldata leg = session.legs[i];
            if (leg.party == address(0)) revert ZeroParty();

            for (uint256 j = i + 1; j < count; ++j) {
                if (session.legs[j].party == leg.party) revert DuplicateParty(leg.party);
            }

            quantityResidual += leg.quantityDelta;
            cashResidual += leg.cashDelta;
        }

        if (quantityResidual != 0) revert QuantityDoesNotNet(quantityResidual);
        if (cashResidual != 0) revert CashDoesNotNet(cashResidual);

        IERC20 securityToken = IERC20(registry.securityOf(session.security).token);
        IERC20 cashToken = IERC20(session.cash);

        // Collect from every party in deficit first, so the contract is funded before
        // it pays anyone out. A short collection reverts the whole session.
        for (uint256 i; i < count; ++i) {
            Leg calldata leg = session.legs[i];
            if (leg.quantityDelta < 0) {
                securityToken.safeTransferFrom(leg.party, address(this), uint256(-leg.quantityDelta));
            }
            if (leg.cashDelta < 0) {
                cashToken.safeTransferFrom(leg.party, address(this), uint256(-leg.cashDelta));
            }
        }

        for (uint256 i; i < count; ++i) {
            Leg calldata leg = session.legs[i];
            if (leg.quantityDelta > 0) {
                securityToken.safeTransfer(leg.party, uint256(leg.quantityDelta));
            }
            if (leg.cashDelta > 0) {
                cashToken.safeTransfer(leg.party, uint256(leg.cashDelta));
            }
        }

        unchecked {
            ++sessionCount;
            grossTradesNetted += grossTrades;
        }

        emit SessionSettled(sessionCount, session.security, count, grossTrades);
    }

    function transfersSaved(Session calldata session, uint256 grossTrades)
        external
        pure
        returns (uint256 gross, uint256 net)
    {
        gross = grossTrades * 2;

        uint256 count = session.legs.length;
        for (uint256 i; i < count; ++i) {
            if (session.legs[i].quantityDelta != 0) ++net;
            if (session.legs[i].cashDelta != 0) ++net;
        }
    }
}
