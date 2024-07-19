// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIDOPool {
    error InvalidParticipateToken(address token);
    error ParticipateWithDifferentToken(address token);
    error AlreadyFinalized();
    error AlreadyCanceled();
    error NotFinalized();
    error NotCanceled();
    error NotStaker(address);
    error NoStaking();
    error NotStarted();
    error AlreadyStarted();
    error FudingGoalNotReached();
    error IDONotEnded();
    error NotClaimable();

    event Participation(address indexed account, address token, uint256 amount, uint256 tokenAllocation);

    event Claim(address indexed account, uint256 idoAmount);

    event ClaimableTimeDelayed(uint256 previousTime, uint256 newTime);
    event IdoEndTimeDelayed(uint256 previousTime, uint256 newTime);
    event Finalized(uint32 indexed IdoRoundId, uint256 fundedUSDValue, uint256 tokensSold, uint256 idoSize);
    event IDOCreated(uint32 indexed idoRoundId, string idoName, address idoToken, uint256 idoPrice, uint256 idoSize, uint256 minimumFundingGoal, uint64 idoStartTime, uint64 idoEndTime, uint64 claimableTime);

    event WhitelistStatusChanged(uint32 indexed idoRoundId, bool status);
    event FyTokenMaxBasisPointsChanged(uint32 indexed idoRoundId, uint16 newFyTokenMaxBasisPoints);
    event IDOCanceled(uint32 indexed idoRoundId, uint256 fundedUSDValue, uint256 tokensSold, uint256 idoSize);
    event RefundClaimed(uint32 indexed idoRoundId, address indexed participant, uint256 amount, uint256 fyAmount);

}
