// Contract extended with view functions for structs
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/StandardIDOPool.sol";

contract TestStandardIDOPool is StandardIDOPool {

    // IDORoundClock getter
    function getIDORoundClock(uint32 idoRoundId) public view returns (
        uint64 idoStartTime,
        uint64 claimableTime,
        uint64 initialClaimableTime,
        uint64 idoEndTime,
        uint64 initialIdoEndTime,
        bool isFinalized,
        bool isCanceled,
        bool isEnabled,
        bool hasNoRegList,
        uint32 parentMetaIdoId
    ) {
        IDOStructs.IDORoundClock storage clock = idoRoundClocks[idoRoundId];
        return (
            clock.idoStartTime,
            clock.claimableTime,
            clock.initialClaimableTime,
            clock.idoEndTime,
            clock.initialIdoEndTime,
            clock.isFinalized,
            clock.isCanceled,
            clock.isEnabled,
            clock.hasNoRegList,
            clock.parentMetaIdoId
        );
    }

    // IDORoundConfig getters (split to avoid stack too deep)
    function getIDORoundConfigPart1(uint32 idoRoundId) public view returns (
        address idoToken,
        uint8 idoTokenDecimals,
        uint16 fyTokenMaxBasisPoints,
        address buyToken,
        address fyToken
    ) {
        IDOStructs.IDORoundConfig storage config = idoRoundConfigs[idoRoundId];
        return (
            config.idoToken,
            config.idoTokenDecimals,
            config.fyTokenMaxBasisPoints,
            config.buyToken,
            config.fyToken
        );
    }

    function getIDORoundConfigPart2(uint32 idoRoundId) public view returns (
        uint256 idoPrice,
        uint256 idoSize,
        uint256 idoTokensSold,
        uint256 minimumFundingGoal,
        uint256 fundedUSDValue
    ) {
        IDOStructs.IDORoundConfig storage config = idoRoundConfigs[idoRoundId];
        return (
            config.idoPrice,
            config.idoSize,
            config.idoTokensSold,
            config.minimumFundingGoal,
            config.fundedUSDValue
        );
    }

    // Getter for totalFunded in IDORoundConfig
    function getTotalFunded(uint32 idoRoundId, address token) public view returns (uint256) {
        return idoRoundConfigs[idoRoundId].totalFunded[token];
    }

    // Getter for accountPositions in IDORoundConfig
    function getAccountPosition(uint32 idoRoundId, address account) public view returns (
        uint256 amount,
        uint256 fyAmount,
        uint256 tokenAllocation
    ) {
        IDOStructs.Position storage position = idoRoundConfigs[idoRoundId].accountPositions[account];
        return (position.amount, position.fyAmount, position.tokenAllocation);
    }

    // MetaIDO getters
    function getMetaIDOInfo(uint32 metaIdoId) public view returns (
        uint64 registrationStartTime,
        uint64 initialRegistrationEndTime,
        uint64 registrationEndTime
    ) {
        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        return (
            metaIDO.registrationStartTime,
            metaIDO.initialRegistrationEndTime,
            metaIDO.registrationEndTime
        );
    }

    // Getter for globalTokenAllocPerIDORound
    function getGlobalTokenAllocPerIDORound(address token) public view returns (uint256) {
        return globalTokenAllocPerIDORound[token];
    }
}
