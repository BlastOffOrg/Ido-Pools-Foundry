// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interface/IERC20Mintable.sol";

contract MockERC20 is ERC20, IERC20Mintable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

