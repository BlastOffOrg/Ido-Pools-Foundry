// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../src/MultiplierContract.sol";

contract MockMultiplierContract is IMultiplierContract {
    mapping(address => UserInfo) private userInfo;

    struct UserInfo {
        uint256 multiplier;
        uint256 rank;
    }

    function setMultiplier(address user, uint256 multiplier, uint256 rank) external {
        userInfo[user] = UserInfo(multiplier, rank);
    }

    function getMultiplier(address user) external view override returns (uint256 multiplier, uint256 rank) {
        UserInfo memory info = userInfo[user];
        return (info.multiplier, info.rank);
    }
}
