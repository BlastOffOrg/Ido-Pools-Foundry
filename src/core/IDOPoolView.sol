// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IDOStorage.sol";
import "../interface/IIDOPool.sol";

abstract contract IDOPoolView is IDOStorage {
    using IDOStructs for *;

    struct UserMetaIDOInfo {
        uint32 metaIdoId;
        uint16 rank;
        uint16 multiplier;
    }

    struct UserParticipationInfo {
        uint32 roundId;
        uint256 fyTokenAmount;
        uint256 buyTokenAmount;
        uint256 idoTokensAllocated;
        uint256 maxAllocation;
    }

    /**
        * @notice Retrieves the total amount funded by a specific participant across multiple IDO rounds, filtered by token type.
        * @param roundIds An array of IDO round identifiers.
        * @param participant The address of the participant.
        * @param tokenType The type of token to filter the amounts (0 for BuyToken, 1 for FyToken, 2 for Both).
        * @return totalAmount The total amount funded by the participant across the specified rounds for the chosen token type.
        */
    function getParticipantFundingByRounds(uint32[] calldata roundIds, address participant, uint8 tokenType) external view returns (uint256 totalAmount) {
        for (uint i = 0; i < roundIds.length; i++) {
            uint32 roundId = roundIds[i];
            require(idoRoundConfigs[roundId].idoToken != address(0), "IDO round does not exist");
            IDOStructs.Position storage position = idoRoundConfigs[roundId].accountPositions[participant];
            if (tokenType == 0) {  // BuyToken
                totalAmount += position.amount - position.fyAmount;
            } else if (tokenType == 1) {  // FyToken
                totalAmount += position.fyAmount;
            } else {  // Both
                totalAmount += position.amount;
            }
        }
        return totalAmount;
    }

    /**
        * @notice Retrieves the total funds raised for specified IDO rounds, filtered by token type.
        * @param roundIds An array of IDO round identifiers.:
        * @param tokenType The type of token to filter the funding amounts (0 for BuyToken, 1 for FyToken, 2 for Both).
        * @return totalRaised The total funds raised in the specified IDO rounds for the chosen token type.
        */
    function getFundsRaisedByRounds(uint32[] calldata roundIds, uint8 tokenType) external view returns (uint256 totalRaised) {
        for (uint i = 0; i < roundIds.length; i++) {
            uint32 roundId = roundIds[i];
            require(idoRoundConfigs[roundId].idoToken != address(0), "IDO round does not exist");
            IDOStructs.IDORoundConfig storage round = idoRoundConfigs[roundId];

            if (tokenType == 0) {  // BuyToken
                totalRaised += round.totalFunded[round.buyToken];
            } else if (tokenType == 1) {  // FyToken
                totalRaised += round.totalFunded[round.fyToken];
            } else {  // Both
                totalRaised += round.fundedUSDValue; 
            }
        }
        return totalRaised;
    }

    /**
        * @notice Retrieves all IDO round IDs associated with a specific MetaIDO.
        * @param metaIdoId The ID of the MetaIDO.
        * @return An array of IDO round IDs associated with the specified MetaIDO.
        */
    function getIDORoundsByMetaIDO(uint32 metaIdoId) external view returns (uint32[] memory) {
        return metaIDOs[metaIdoId].roundIds;
    }

    /**
        * @notice Retrieves the associated MetaIDO ID for a given IDO round.
        * @param idoRoundId The ID of the IDO round.
        * @return The ID of the associated MetaIDO.
        */
    function getMetaIDOByIDORound(uint32 idoRoundId) external view returns (uint32) {
        return idoRoundClocks[idoRoundId].parentMetaIdoId;
    }


    /**
        * @notice Checks if a user is registered for a specific MetaIDO.
        * @param user The address of the user to check.
        * @param metaIdoId The ID of the MetaIDO.
        * @return A boolean indicating whether the user is registered for the specified MetaIDO.
        */
    function getCheckUserRegisteredForMetaIDO(address user, uint32 metaIdoId) external view returns (bool) {
        return metaIDOs[metaIdoId].isRegistered[user];
    }

    /**
        * @notice Retrieves a user's registration information for all MetaIDOs they are registered for.
        * @param user The address of the user.
        * @return An array of UserMetaIDOInfo structs containing the user's registration details for each MetaIDO.
        */
    function getUserMetaIDOInfo(address user) external view returns (UserMetaIDOInfo[] memory) {
        uint32[] memory registeredMetaIDOs = new uint32[](nextMetaIdoId);
        uint32 count = 0;

        // First, count the number of MetaIDOs the user is registered for
        for (uint32 i = 0; i < nextMetaIdoId; i++) {
            if (metaIDOs[i].isRegistered[user]) {
                registeredMetaIDOs[count] = i;
                count++;
            }
        }

        // Create an array of the correct size
        UserMetaIDOInfo[] memory userInfo = new UserMetaIDOInfo[](count);

        // Populate the array with user's rank and multiplier for each registered MetaIDO
        for (uint32 i = 0; i < count; i++) {
            uint32 metaIdoId = registeredMetaIDOs[i];
            userInfo[i] = UserMetaIDOInfo({
                metaIdoId: metaIdoId,
                rank: metaIDOs[metaIdoId].userRank[user],
                multiplier: metaIDOs[metaIdoId].userMaxAllocMult[user]
            });
        }

        return userInfo;
    }

/**
     * @notice Retrieves participation information for a user across multiple IDO rounds
     * @dev This function aggregates user participation data for specified IDO rounds
     * @param user The address of the user to query
     * @param idoRoundIds An array of IDO round IDs to check for user participation
     * @return An array of UserParticipationInfo structs containing participation details
     */
    function getUserParticipationInfo(address user, uint32[] calldata idoRoundIds) external view returns (UserParticipationInfo[] memory) {
        UserParticipationInfo[] memory participations = new UserParticipationInfo[](idoRoundIds.length);
        uint256 count = 0;

        for (uint256 i = 0; i < idoRoundIds.length; i++) {
            uint32 roundId = idoRoundIds[i];
            IDOStructs.IDORoundConfig storage config = idoRoundConfigs[roundId];
            IDOStructs.Position storage position = config.accountPositions[user];
            IDOStructs.IDORoundSpec storage spec = idoRoundSpecs[roundId];

            if (position.amount > 0 || spec.specsInitialized) {
                uint256 maxAllocation = getUserMaxAlloc(roundId, user);

                participations[count] = UserParticipationInfo(
                    roundId,
                    position.fyAmount,
                    position.amount - position.fyAmount,
                    position.tokenAllocation,
                    maxAllocation
                );
                count++;
            }
        }

        assembly { mstore(participations, count) }
        return participations;
    }

    /**
         * @notice Calculates the maximum allocation for a participant in a specific IDO round
         * @dev This function takes into account the IDO round specifications, registration requirements,
         *      user rank, and multipliers to determine the maximum allocation
         * @param idoRoundId The ID of the IDO round
         * @param participant The address of the participant
         * @return maxAllocation The maximum allocation for the participant in the IDO round
         *
         * The function returns 0 in the following cases:
         * - If the IDO round specifications are not initialized
         * - If registration is required and the participant is not registered
         * - If the participant's rank is not eligible for the IDO round
         *
         * The calculation of maxAllocation considers:
         * - The base maxAlloc from the IDO round specifications
         * - The participant's rank and whether rank checks are enabled
         * - The participant's multiplier and the IDO round's maxAllocMultiplier, if multipliers are enabled
         */
    function getUserMaxAlloc(
        uint32 idoRoundId,
        address participant
    ) public view returns (uint256 maxAllocation) {
        IDOStructs.IDORoundSpec storage spec = idoRoundSpecs[idoRoundId];

        // Check if specs are initialized
        if (!spec.specsInitialized) {
            return 0;
        }

        uint32 parentMetaIdoId = idoRoundClocks[idoRoundId].parentMetaIdoId;

        // Check for no registration list case
        if (!idoRoundClocks[idoRoundId].hasNoRegList) {
            // If registration is required, check if the participant is registered
            if (!metaIDOs[parentMetaIdoId].isRegistered[participant]) {
                return 0; // Return 0 if the participant is not registered
            }
        }

        uint16 userRank = metaIDOs[parentMetaIdoId].userRank[participant];
        uint16 userMultiplier = metaIDOs[parentMetaIdoId].userMaxAllocMult[participant];

        bool isEligible = spec.noRank || (userRank >= spec.minRank && userRank <= spec.maxRank);

        if (!isEligible) {
            return 0;
        }

        maxAllocation = spec.maxAlloc;

        if (!spec.noMultiplier) {
            // userMultiplier is a simple integer, maxAllocMultiplier is in basis points
            maxAllocation = (maxAllocation * userMultiplier * spec.maxAllocMultiplier) / 10_000;
        }

        return maxAllocation;
    }

    /**
     * @notice Retrieves a paginated list of participants for a specific IDO round
     * @dev This function returns a portion of the participants array for the given IDO round,
     *      using startIndex and pageSize for pagination
     * @param idoRoundId The ID of the IDO round
     * @param startIndex The starting index for pagination
     * @param pageSize The number of participants to return per page
     * @return participants An array of participant addresses for the specified IDO round and page
     * @return nextIndex The starting index for the next page, or 0 if this is the last page
     */
    function getIDOParticipants(
        uint32 idoRoundId,
        uint256 startIndex,
        uint256 pageSize
    ) external view returns (address[] memory participants, uint256 nextIndex) {
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        uint256 totalParticipants = idoConfig.idoParticipants.length;
        
        require(startIndex < totalParticipants, "Start index out of bounds");

        // Determine the actual page size (might be smaller for the last page)
        uint256 actualPageSize = pageSize;
        if (startIndex + pageSize > totalParticipants) {
            actualPageSize = totalParticipants - startIndex;
        }

        participants = new address[](actualPageSize);

        // Fill the participants array from the idoParticipants Array
        for (uint256 i = 0; i < actualPageSize; i++) {
            participants[i] = idoConfig.idoParticipants[startIndex + i];
        }

        // Set the next index
        nextIndex = (startIndex + actualPageSize < totalParticipants) ? startIndex + actualPageSize : 0;

        return (participants, nextIndex);
    }

    /**
     * @notice Retrieves paginated information about participants across one or multiple IDO rounds
     * @dev This function aggregates participant data for the specified IDO rounds,
     *      ensuring all rounds use the same IDO token. It returns data in pages to handle large numbers of participants.
     * @param roundIds An array of IDO round identifiers to query
     * @param startIndex The starting index for pagination
     * @param pageSize The number of participants to return per page
     * @return participants An array of participant addresses for the current page
     * @return totalAmounts An array of total amounts contributed by each participant on the current page
     * @return totalIdoTokenAmounts An array of total IDO token amounts allocated to each participant on the current page
     * @return nextIndex The starting index for the next page, or 0 if this is the last page
     */
    function getParticipantsInfo(
        uint32[] calldata roundIds,
        uint256 startIndex,
        uint256 pageSize
    ) external view returns (
        address[] memory participants,
        uint256[] memory totalAmounts,
        uint256[] memory totalIdoTokenAmounts,
        uint256 nextIndex
    ) {
        require(roundIds.length > 0, "At least one round ID is required");
        require(pageSize > 0 && pageSize <= 500, "Invalid page size");

        // Check if all rounds have the same IDO token
        address idoToken = idoRoundConfigs[roundIds[0]].idoToken;
        for (uint i = 1; i < roundIds.length; i++) {
            require(idoRoundConfigs[roundIds[i]].idoToken == idoToken, "All rounds must have the same IDO token");
        }

        // Collect all unique participants
        address[] memory allParticipants = new address[](0);
        for (uint i = 0; i < roundIds.length; i++) {
            address[] memory roundParticipants = idoRoundConfigs[roundIds[i]].idoParticipants;
            for (uint j = 0; j < roundParticipants.length; j++) {
                bool isUnique = true;
                for (uint k = 0; k < allParticipants.length; k++) {
                    if (allParticipants[k] == roundParticipants[j]) {
                        isUnique = false;
                        break;
                    }
                }
                if (isUnique) {
                    address[] memory newAllParticipants = new address[](allParticipants.length + 1);
                    for (uint k = 0; k < allParticipants.length; k++) {
                        newAllParticipants[k] = allParticipants[k];
                    }
                    newAllParticipants[allParticipants.length] = roundParticipants[j];
                    allParticipants = newAllParticipants;
                }
            }
        }

        uint256 totalUniqueParticipants = allParticipants.length;
        require(startIndex < totalUniqueParticipants, "Start index out of bounds");

        // Determine the actual page size
        uint256 actualPageSize = (startIndex + pageSize > totalUniqueParticipants) 
            ? totalUniqueParticipants - startIndex 
            : pageSize;

        participants = new address[](actualPageSize);
        totalAmounts = new uint256[](actualPageSize);
        totalIdoTokenAmounts = new uint256[](actualPageSize);

        for (uint i = 0; i < actualPageSize; i++) {
            uint256 participantIndex = startIndex + i;
            address participant = allParticipants[participantIndex];
            participants[i] = participant;

            for (uint j = 0; j < roundIds.length; j++) {
                IDOStructs.Position storage position = idoRoundConfigs[roundIds[j]].accountPositions[participant];
                totalAmounts[i] += position.amount;
                totalIdoTokenAmounts[i] += position.tokenAllocation;
            }
        }

        // Calculate next index
        nextIndex = (startIndex + actualPageSize < totalUniqueParticipants) ? startIndex + actualPageSize : 0;

        return (participants, totalAmounts, totalIdoTokenAmounts, nextIndex);
    }
}

