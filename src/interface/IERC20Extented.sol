// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


abstract contract IERC20Extented is IERC20 {
    function decimals() public virtual returns (uint8);
}