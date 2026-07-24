// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";

/// @title SafeTransfer
/// @notice Transfer helpers that treat a missing return value as success.
/// @dev Some tokenized equity wrappers predate the ERC20 return-value convention and
///      return nothing at all. Requiring a bool from those tokens reverts on a transfer
///      that actually succeeded, so decode only when there is data to decode.
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
        if (data.length == 0) return true;
        if (data.length != 32) return false;
        return abi.decode(data, (bool));
    }
}
