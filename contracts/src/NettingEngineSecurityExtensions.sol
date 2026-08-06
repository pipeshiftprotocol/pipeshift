// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract NettingEngineSecurityExtensions {
    error ReentrancyGuardReentrantCall();
    error UnauthorizedSettler(address caller);

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status = NOT_ENTERED;

    modifier nonReentrantSettlement() {
        if (_status == ENTERED) revert ReentrancyGuardReentrantCall();
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }

    function validateSettlerPermission(address caller, address buyer, address seller, address venue) internal pure {
        if (caller != buyer && caller != seller && caller != venue) {
            revert UnauthorizedSettler(caller);
        }
    }
}
