// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@ozv5/contracts/token/ERC20/ERC20.sol";

contract BasicToken is ERC20 {
    constructor() ERC20("BasicToken", "BasicTkn") {
        _mint(msg.sender, 1_000_000_000 * (10 ** uint256(decimals())));
    }
}


