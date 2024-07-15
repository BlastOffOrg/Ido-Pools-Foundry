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

    event Participation(address indexed account, address token, uint256 amount);

    event Claim(address indexed account, uint256 idoAmount);

    event ClaimableTimeDelayed(uint256 previousTime, uint256 newTime);
    event IdoEndTimeDelayed(uint256 previousTime, uint256 newTime);
    event Finalized(uint256 idoSize, uint256 fundedUSDValue);

    event IDOCreated(uint32 indexed idoId, string idoName, address idoToken, uint256 idoPrice, uint256 idoSize, uint256 minimumFundingGoal, uint64 idoStartTime, uint64 idoEndTime, uint64 claimableTime);

    event WhitelistStatusChanged(uint32 indexed idoId, bool status);
    event CapExceedStatusChanged(uint32 indexed idoId, bool status);
    event FyTokenMaxBasisPointsChanged(uint32 indexed idoId, uint16 newFyTokenMaxBasisPoints);
}
