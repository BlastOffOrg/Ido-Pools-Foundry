// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIDOPool {
    error InvalidParticipateToken(address token);
    error ParticipateWithDifferentToken(address token);
    error AlreadyFinalized();
    error NotFinalized();
    error NotStaker(address);
    error NoStaking();
    error NotStarted();
    error AlreadyStarted();
    error FudingGoalNotReached();
    error IDONotEnded();
    error NotClaimable();

    struct Position {
        uint256 fyAmount;
        uint256 amount;
    }

    event Participation(address indexed account, address token, uint256 amount);

    event Claim(address indexed account, uint256 idoAmount, uint256 refundAmount);

    event ClaimableTimeDelayed(uint256 previousTime, uint256 newTime);
    event IdoEndTimeDelayed(uint256 previousTime, uint256 newTime);
    event Finalized(uint256 idoSize, uint256 fundedUSDValue);

    function participate(address recipient, address token, uint256 amount) external payable;

    function claim(address staker) external;
}
