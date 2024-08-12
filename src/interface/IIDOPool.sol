// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIDOPool {
    error InvalidParticipateToken(address token);
    error ParticipateWithDifferentToken(address token);
    error AlreadyFinalized();
    error NotEnabled();
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
    event RefundClaim(uint32 indexed idoRoundId, address indexed participant, uint256 amount, uint256 buyAmount, uint256 fyTokens);
    event IDOEnabled(uint32 indexed IdoRoundId, address tokenAddress, uint256 idoSize, uint256 newTotalAllocation, uint256 contractTokenBalance);
    event RoundAddedToMetaIDO(uint32 indexed idoRoundId, uint32 indexed metaIdoId);
    event RoundRemovedFromMetaIDO(uint32 indexed idoRoundId, uint32 indexed metaIdoId);

    event MetaIDOCreated(uint32 indexed metaIdoId, uint64 registrationStartTime, uint64 registrationEndTime);
    event MetaIDORegEndTimeDelayed(uint32 indexed metaIdoId, uint64 previousEndTime, uint64 newEndTime);
    event UserRegistered(uint32 indexed metaIdoId, address indexed user, uint16 rank, uint16 multiplier);
    event UsersAdminRegistered(uint32 indexed metaIdoId, address[] users);
    event UsersAdminRemoved(uint32 indexed metaIdoId, address[] users);
    event HasNoRegListEnabled(uint32 indexed idoRoundId);
    event IDORoundSpecsSet( uint32 indexed idoRoundId, uint16 minRank, uint16 maxRank, uint256 maxAlloc, uint256 minAlloc, uint16 maxAllocMultiplier, bool noMultiplier, bool noRank);
    event MultiplierContractUpdated(address indexed oldContract, address indexed newContract);
    event MultiplierContractUpdateProposed(address proposedAddress, uint256 unlockTime);
}
