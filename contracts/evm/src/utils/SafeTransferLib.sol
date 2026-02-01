// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
  function transfer(address to, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function balanceOf(address owner) external view returns (uint256);
}

library SafeTransferLib {
  function safeTransfer(IERC20 token, address to, uint256 amount) internal {
    (bool ok, bytes memory data) = address(token).call(
      abi.encodeWithSelector(token.transfer.selector, to, amount)
    );
    require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
  }

  function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
    (bool ok, bytes memory data) = address(token).call(
      abi.encodeWithSelector(token.transferFrom.selector, from, to, amount)
    );
    require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
  }
}
