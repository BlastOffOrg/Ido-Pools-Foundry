// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../interface/IERC20Rebasing.sol";

contract MockRebaseERC20 is ERC20("MockERC20", "MOCK"), IERC20Rebasing {
  mapping(address => uint256) claimable;

  function configure(RebaseYieldMode) external override returns (uint256) {}

  function claim(
    address recipient,
    uint256 amount
  ) external override returns (uint256) {
    claimable[msg.sender] -= amount;

    _mint(recipient, amount);
    return amount;
  }

  function getClaimableAmount(
    address account
  ) external view override returns (uint256) {
    return claimable[account];
  }

  function setClaimableAmount(address account, uint256 amount) public {
    claimable[account] = amount;
  }

  function mint(address _recipient, uint256 _amount) external override {
    _mint(_recipient, _amount);
  }
}
