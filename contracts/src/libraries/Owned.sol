// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Owned {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferStarted(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);

    error NotOwner(address caller);
    error NotPendingOwner(address caller);
    error ZeroOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    constructor(address owner_) {
        if (owner_ == address(0)) revert ZeroOwner();
        owner = owner_;
        emit OwnershipTransferred(address(0), owner_);
    }

    function transferOwnership(address to) external onlyOwner {
        if (to == address(0)) revert ZeroOwner();
        pendingOwner = to;
        emit OwnershipTransferStarted(msg.sender, to);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner(msg.sender);

        address previous = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(previous, owner);
    }
}
