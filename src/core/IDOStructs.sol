// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library IDOStructs {
    struct Position {
        uint256 amount; // Total amount funded
        uint256 fyAmount; // Amount funded in fyToken
        uint256 tokenAllocation;
    }

    struct IDORoundSpec {
        uint16 minRank; 
        uint16 maxRank; 
        uint256 maxAlloc; 
        uint256 minAlloc; 
        uint16 maxAllocMultiplier; // In basis points. 
        bool noMultiplier; 
        bool noRank; 
        bool specsInitialized; 
    }

    struct IDORoundClock {
        uint64 idoStartTime;
        uint64 claimableTime;
        uint64 initialClaimableTime;
        uint64 idoEndTime;
        uint64 initialIdoEndTime;
        uint32 parentMetaIdoId;
        bool isFinalized;
        bool isCanceled;
        bool isEnabled;
        bool hasNoRegList;
    }

    struct IDORoundConfig {
        address idoToken;
        uint8 idoTokenDecimals;
        uint16 fyTokenMaxBasisPoints;
        address buyToken;
        address fyToken;
        uint256 idoPrice;
        uint256 idoSize;
        uint256 idoTokensSold;
        uint256 idoTokensClaimed;
        uint256 minimumFundingGoal;
        uint256 fundedUSDValue;
        mapping(address => uint256) totalFunded;
        mapping(address => Position) accountPositions;
    }

    struct MetaIDO {
        uint32[] roundIds; 
        uint64 registrationStartTime;
        uint64 initialRegistrationEndTime;
        uint64 registrationEndTime;
        mapping(address => bool) isRegistered;
        mapping(address => uint16) userRank;
        mapping(address => uint16) userMaxAllocMult;
    }
}
