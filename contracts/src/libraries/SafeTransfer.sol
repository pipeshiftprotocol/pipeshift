// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";

library SafeTransfer {
    error TransferFailed(address token, address from, address to, uint256 value);

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));

        if (!_succeeded(ok, data)) revert TransferFailed(address(token), from, to, value);
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool ok, bytes memory data) = address(token).call(abi.encodeCall(IERC20.transfer, (to, value)));

        if (!_succeeded(ok, data)) revert TransferFailed(address(token), address(this), to, value);
    }

    function _succeeded(bool ok, bytes memory data) private pure returns (bool) {
        if (!ok) return false;
        return abi.decode(data, (bool));
    }
}
