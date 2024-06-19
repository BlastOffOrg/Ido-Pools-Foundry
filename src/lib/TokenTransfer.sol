// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IERC20Mintable.sol";

library TokenTransfer {
  using SafeERC20 for IERC20;
  error InvalidTokenAmounts(uint256 amount);

  function _depositToken(address token, address from, uint256 amount) internal {
    if (token == address(0)) {
      if (amount != msg.value) revert InvalidTokenAmounts(amount);
    } else {
      IERC20(token).safeTransferFrom(from, address(this), amount);
    }
  }

  function _depositAndReturnSpare(address token, address from, address to, uint256 amount) internal {
    if (token == address(0)) {
      if (amount > msg.value) revert InvalidTokenAmounts(amount);
      payable(to).transfer(amount);
      payable(from).transfer(msg.value - amount);
    } else {
      IERC20(token).safeTransferFrom(from, to, amount);
    }
  }

  function _transferToken(address token, address to, uint256 amount) internal {
    if (token == address(0)) {
      if (address(this).balance < amount) revert InvalidTokenAmounts(amount);
      payable(to).transfer(amount);
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
  }

  function _mintToken(address token, address to, uint256 amount) internal {
    IERC20Mintable(token).mint(to, amount);
  }
}
