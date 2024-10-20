// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interface/IIDOPool.sol";
import "../lib/TokenTransfer.sol";
import "./IDOStorage.sol";
import "./IDOPoolView.sol";
import "./BlastYieldAbstract.sol";

abstract contract IDOPoolAbstract is IIDOPool, Ownable2StepUpgradeable, IDOStorage, IDOPoolView, BlastYieldAbstract {
    using IDOStructs for *;
    // Make the structs available in the global namespace

    function __IDOPoolAbstract_init(address treasury_, address _multiplierContract) internal onlyInitializing {
        treasury = treasury_;
        multiplierContract = IMultiplierContract(_multiplierContract);
        __Ownable2Step_init();
        __BlastYieldAbstract_init();

    }

    // ============================================= 
    // =============== Owner IDORound ==============
    // =============================================

    /**
         * @notice Creates a new IDO round with specified parameters
         * @dev Only callable by the owner
         * @param idoName Name of the IDO
         * @param idoToken Address of the token being offered in the IDO
         * @param buyToken Address of the token used to buy into the IDO
         * @param fyToken Address of the FY token (should be same value as buyToken)
         * @param idoPrice Price of 1 whole IDO token in buyToken/fyToken's smallest units (excluding IDO token's decimals)
         * @param idoSize Total amount of idoToken in raw token amount (including decimals)
         * @param minimumFundingGoal Minimum funding goal in value for the IDO (IdoPrice * IdoSize / IdoTokenDecimals)
         * @param fyTokenMaxBasisPoints Maximum percentage of fyToken contributions in basis points. Should not exceed 10_000
         * @param idoStartTime Start time of the IDO
         * @param idoEndTime End time of the IDO
         * @param claimableTime Time when tokens become claimable
         * @custom:throws ImpossibleFundingGoal if the minimum funding goal is higher than the total IDO value
         */
    function createIDORound(
        string calldata idoName,
        address idoToken,
        address buyToken,
        address fyToken,
        uint256 idoPrice,
        uint256 idoSize,
        uint256 minimumFundingGoal,
        uint16 fyTokenMaxBasisPoints,
        uint64 idoStartTime,
        uint64 idoEndTime,
        uint64 claimableTime
    ) external onlyOwner {
        //"End time must be after start time"
        if (idoEndTime <= idoStartTime) revert Time1MustBeAfterTime2(idoEndTime, idoStartTime);
        //"Claim time must be after end time"
        if (claimableTime <= idoEndTime) revert Time1MustBeAfterTime2(claimableTime, idoEndTime);
        uint32 idoRoundId = nextIdoRoundId ++; // postfix increment
        idoRoundClocks[idoRoundId] = IDOStructs.IDORoundClock({
            parentMetaIdoId: 0,
            idoStartTime: idoStartTime,
            claimableTime: claimableTime,
            initialClaimableTime: claimableTime,
            idoEndTime: idoEndTime,
            initialIdoEndTime: idoEndTime,
            isFinalized: false,
            isCanceled: false,
            isEnabled: false,
            hasNoRegList: false
        });

        //IDORoundConfig needs to be assigned like this, Nested mapping error.
        IDOStructs.IDORoundConfig storage config = idoRoundConfigs[idoRoundId];
        config.idoToken = idoToken;
        config.idoTokenDecimals = ERC20(idoToken).decimals();
        config.buyToken = buyToken;
        config.fyToken = fyToken;
        config.idoPrice = idoPrice;
        config.idoSize = idoSize;
        config.idoTokensSold = 0;
        config.idoTokensClaimed = 0;
        config.minimumFundingGoal = minimumFundingGoal;
        config.fundedUSDValue = 0;

        //"Basis points cannot exceed 10000"
        if (fyTokenMaxBasisPoints > 10000) revert BasisPointsExceeded();

        config.fyTokenMaxBasisPoints = fyTokenMaxBasisPoints;

        if (minimumFundingGoal > idoSize * idoPrice / 10**config.idoTokenDecimals) revert ImpossibleFundingGoal();

        emit IDOCreated(idoRoundId, idoName, idoToken, idoPrice, idoSize, minimumFundingGoal, idoStartTime, idoEndTime, claimableTime);
    }

    /**
        * @notice Finalize the IDO pool for a specific IDO.
        * @dev This function finalizes the given IDO, calculates the total value of USD funded, and determines the IDO size.
        *       It cannot be finalized if the IDO has not reached its end time, the minimum funding goal is not met,
        *       or if it's already finalized or canceled.
        *       It also reduces the global token allocation by the amount of unsold tokens.
        * @param idoRoundId The ID of the IDO to finalize.
        * @custom:throws AlreadyCanceled if the IDO has been canceled
        * @custom:throws AlreadyFinalized if the IDO has already been finalized
        * @custom:throws IDONotEnded if the IDO end time hasn't been reached
        * @custom:throws FundingGoalNotReached if the minimum funding goal wasn't met
        */
    function finalizeRound(uint32 idoRoundId) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        if (idoClock.isCanceled) revert AlreadyCanceled();
        if (idoClock.isFinalized) revert AlreadyFinalized();
        
        uint256 idoTokensSold = idoConfig.idoTokensSold;
        uint256 idoSize = idoConfig.idoSize;

        uint64 idoEndTime = idoClock.idoEndTime;
        if (block.timestamp < idoEndTime) revert IDONotEnded(idoEndTime);

        uint256 fundedUSDValue = idoConfig.fundedUSDValue;
        uint256 minimumFundingGoal = idoConfig.minimumFundingGoal;

        if (fundedUSDValue < minimumFundingGoal) revert FundingGoalNotReached(fundedUSDValue, minimumFundingGoal);

        idoClock.isFinalized = true;
        // Reduce global token allocation by the unsold tokens
        uint256 unsoldTokens = idoSize - idoTokensSold;
        globalTokenAllocPerIDORound[idoConfig.idoToken] -= unsoldTokens;

        emit Finalized(idoRoundId, fundedUSDValue, idoTokensSold, idoSize);
    }

    /**
        * @notice Cancels an IDO round. This can only be done by the owner, and allows participants to claim refunds.
        * @dev Sets the `isCanceled` flag and prevents further participation or finalization.
        *       Reduces global token allocation based on whether the round is finalized or not.
        * @param idoRoundId The ID of the IDO to cancel.
        * @custom:throws AlreadyCanceled if the IDO has already been canceled
        */
    function cancelIDORound(uint32 idoRoundId) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        if (idoClock.isCanceled) revert AlreadyCanceled();

        idoClock.isCanceled = true;

        // Reduce global token allocation if the round was previously enabled
        if (idoClock.isEnabled) {
            if (idoClock.isFinalized) {
                // For finalized rounds, remove only unclaimed tokens
                uint256 unclaimedTokens = idoConfig.idoTokensSold - idoConfig.idoTokensClaimed;
                globalTokenAllocPerIDORound[idoConfig.idoToken] -= unclaimedTokens;
            } else {
                // For non-finalized rounds, remove the entire idoSize
                globalTokenAllocPerIDORound[idoConfig.idoToken] -= idoConfig.idoSize;
            }
        }

        emit IDOCanceled(idoRoundId, idoConfig.fundedUSDValue, idoConfig.idoTokensSold, idoConfig.idoSize); 
    }

    /**
         * @notice This function enables an IDO round if it meets all requirements, including sufficient token reserves across all rounds.
         * @dev Only callable by the owner. Ensures tokens for this and all other enabled rounds do not exceed the token balance.
         *      Checks if the round is not already enabled, initialized, canceled, or finalized.
         * @param idoRoundId The identifier of the IDO round to enable.
         * @custom:throws IDORoundIsEnabled if the round is already enabled
         * @custom:throws IDORoundNotInitialized if the round is not properly initialized
         * @custom:throws AlreadyCanceled if the round has been canceled
         * @custom:throws AlreadyFinalized if the round has been finalized
         * @custom:throws IDORoundSpecsNotSet if the round specifications haven't been set
         * @custom:throws InsufficientFundsToEnableIDORound if there are not enough tokens to enable the round
         */
    function enableIDORound(uint32 idoRoundId) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDOStructs.IDORoundSpec storage idoSpec = idoRoundSpecs[idoRoundId];

        if (idoClock.isEnabled) revert IDORoundIsEnabled();
        if (idoClock.idoStartTime == 0) revert IDORoundNotInitialized();
        if (idoClock.isCanceled) revert AlreadyCanceled();
        if (idoClock.isFinalized) revert AlreadyFinalized();

        if (!idoSpec.specsInitialized) revert IDORoundSpecsNotSet();
        // Calculate new total allocation for this token, including already allocated tokens
        uint256 newTotalAllocation = globalTokenAllocPerIDORound[idoConfig.idoToken] + idoConfig.idoSize;

        // Checking the token balance in the contract for the IDO token
        uint256 tokenBalance = IERC20(idoConfig.idoToken).balanceOf(address(this));
        if (tokenBalance < newTotalAllocation) revert InsufficientFundsToEnableIDORound();

        // Update global token allocation
        globalTokenAllocPerIDORound[idoConfig.idoToken] = newTotalAllocation;

        // Enable the round
        idoClock.isEnabled = true;

        emit IDOEnabled(idoRoundId, idoConfig.idoToken, idoConfig.idoSize, newTotalAllocation, tokenBalance);

    }

    /**
         * @notice Enables the no registration list requirement for a specific IDO round if it's not already enabled.
         * @dev Sets `hasNoRegList` to true for the specified IDO round, indicating that participants do not need to be registered.
         *      Does nothing if `hasNoRegList` is already true.
         * @param idoRoundId The identifier of the IDO round to modify.
         */
    function enableHasNoRegList(uint32 idoRoundId) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];

        // Disabled: Can be set anytime. Does nothing if it has already been set before for a specific round.
        if(!idoClock.hasNoRegList) {
        idoClock.hasNoRegList = true;

        emit HasNoRegListEnabled(idoRoundId);
        }
    }

    /**
        * @notice Sets the maximum allowable contribution with fyTokens as a percentage of the total IDO size, measured in basis points.
        * @dev Updates the maximum basis points for fyToken contributions for a specified IDO. This setting is locked once the IDO starts.
        * @param idoRoundId The identifier for the specific IDO.
        * @param newFyTokenMaxBasisPoints The new maximum basis points (bps) limit for fyToken contributions. One basis point equals 0.01%.
        * Can only be set to a value between 0 and 10,000 basis points (0% to 100%).
        */
    function setFyTokenMaxBasisPoints(uint32 idoRoundId, uint16 newFyTokenMaxBasisPoints) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        //"Basis points cannot exceed 10000"
        if (newFyTokenMaxBasisPoints > 10000) revert BasisPointsExceeded();
        //"Cannot change settings after IDO start"
        if (block.timestamp >= idoClock.idoStartTime) revert AlreadyStarted();

        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        idoConfig.fyTokenMaxBasisPoints = newFyTokenMaxBasisPoints;

        emit FyTokenMaxBasisPointsChanged(idoRoundId, newFyTokenMaxBasisPoints);
    }


    // =================================================== 
    // =============== Owner Delay IDORound ==============
    // ===================================================



    /**
        * @notice Delays the claimable time for a specific IDO Round.
        * @dev This function updates the claimable time for the given IDO Round to a new time, provided the new time is 
    * later than the current claimable time, later than the idoEndTime 
    * and does not exceed two weeks from the initial claimable time.
        * @param idoRoundId The ID of the IDO Round to update.
        * @param _newTime The new claimable time to set.
        */
    function delayClaimableTime(uint32 idoRoundId, uint64 _newTime) external onlyOwner {
        IDOStructs.IDORoundClock storage ido = idoRoundClocks[idoRoundId];
        //"New claimable time must be after current claimable time"
        if (_newTime <= ido.claimableTime) revert NewTimeNotLaterThanCurrent();
        if (_newTime <= ido.idoEndTime) revert Time1MustBeAfterTime2(_newTime, ido.idoEndTime);  
        if (_newTime > ido.initialClaimableTime + 2 weeks) revert NewTimeExceedsTwoWeeksLimit();
        
        emit ClaimableTimeDelayed(ido.claimableTime, _newTime);

        ido.claimableTime = _newTime;
    }

    /**
        * @notice Delays the end time for a specific IDO.
        * @dev This function updates the end time for the given IDO to a new time, provided the new time is later 
    * than the current end time and does not exceed two weeks from the initial end time.
        * @param idoRoundId The ID of the IDO to update.
        * @param _newTime The new end time to set.
        */
    function delayIdoEndTime(uint32 idoRoundId, uint64 _newTime) external onlyOwner {
        IDOStructs.IDORoundClock storage ido = idoRoundClocks[idoRoundId];
        //"New IDO end time must be after current IDO end time"
        if (_newTime <= ido.idoEndTime) revert NewTimeNotLaterThanCurrent();
        if (_newTime > ido.initialIdoEndTime + 2 weeks) revert NewTimeExceedsTwoWeeksLimit();
        emit IdoEndTimeDelayed(ido.idoEndTime, _newTime);

        ido.idoEndTime = _newTime;
    }


    // =================================================== 
    // =============== Participant IDORound ==============
    // ===================================================


    /**
        * @notice Allows participants to claim a refund for a canceled IDO round.
        * @dev This function refunds both buyToken and fyToken contributions, updates the IDO state,
        * and emits a RefundClaim event.
        * @param idoRoundId The ID of the canceled IDO round.
        */
    function claimRefund(uint32 idoRoundId) external {
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDOStructs.Position storage pos = idoConfig.accountPositions[msg.sender];

        if (!idoRoundClocks[idoRoundId].isCanceled) revert NotCanceled();
        if (pos.amount == 0) revert NoFundsToRefund();

        uint256 refundAmountFyToken = pos.fyAmount;
        uint256 refundAmountTokens = pos.amount;
        uint256 refundAmountBuyToken = refundAmountTokens - refundAmountFyToken;

        idoConfig.idoTokensSold -= pos.tokenAllocation;
        idoConfig.fundedUSDValue -= pos.amount; 
        idoConfig.totalFunded[idoConfig.fyToken] -= refundAmountFyToken;
        idoConfig.totalFunded[idoConfig.buyToken] -= refundAmountBuyToken;

        delete idoConfig.accountPositions[msg.sender]; 

        if (refundAmountFyToken > 0) {
            TokenTransfer._transferToken(idoConfig.fyToken, msg.sender, refundAmountFyToken);
        }

        if (refundAmountBuyToken > 0) {
            TokenTransfer._transferToken(idoConfig.buyToken, msg.sender, refundAmountBuyToken);
        }

        emit RefundClaim(idoRoundId, msg.sender, refundAmountTokens, refundAmountBuyToken, refundAmountFyToken);
    }


    /**
        * @notice Transfer the staker's funds to the treasury for a specific IDO.
        * @dev This function transfers the staker's funds to the treasury.
        * @param idoRoundId The ID of the IDO.
        * @param pos The position of the staker.
        */
    function _depositToTreasury(uint32 idoRoundId, IDOStructs.Position memory pos) internal {
        IDOStructs.IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        uint256 fyAmount = pos.fyAmount;
        uint256 amount = pos.amount;

        if (fyAmount > 0) TokenTransfer._transferToken(ido.fyToken, treasury, fyAmount);
        if (amount - fyAmount > 0) TokenTransfer._transferToken(ido.buyToken, treasury, amount - fyAmount);
    }


    /**
        * @notice Participate in a specific IDO.
        * @dev This function allows a user to participate in a given IDO by contributing a specified amount of tokens.
        * It performs basic participation checks, round specification checks, and updates the participant's position.
        * The token used for participation must be either the buyToken or fyToken of the IDO.
        * @param idoRoundId The ID of the IDO to participate in.
        * @param token The address of the token used to participate, must be either the buyToken or fyToken.
        * @param amount The amount of the token to participate with.
        */
    function participateInRound(
        uint32 idoRoundId, 
        address token, 
        uint256 amount
    ) external {
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];

        if (idoClock.isFinalized) revert AlreadyFinalized();
        if (!idoClock.isEnabled) revert NotEnabled();
        if (idoClock.isCanceled) revert AlreadyCanceled();
        if(block.timestamp < idoClock.idoStartTime) revert NotStarted();

        _basicParticipationCheck(idoConfig, idoClock, msg.sender, token, amount); // Standard participation checks

        // Calculate token allocation and check for funding cap excess
        uint256 tokenAllocation = (amount * 10**idoConfig.idoTokenDecimals) / idoConfig.idoPrice;
        uint256 newTotalTokens = idoConfig.idoTokensSold + tokenAllocation;
        if (newTotalTokens > idoConfig.idoSize) revert FundingCapExceeded();

        (uint16 participantRank, uint16 participantMultiplier) = _getParticipantData(idoRoundId, msg.sender);

        _roundSpecsParticipationCheck(idoRoundId, msg.sender, amount, participantRank, participantMultiplier);     // Round specs check

        IDOStructs.Position storage position = idoConfig.accountPositions[msg.sender];
        
        if (position.amount == 0) {
        // This is the first time this participant is joining this round
        idoConfig.idoParticipants.push(msg.sender);
        }

        if (token == idoConfig.fyToken) {
            position.fyAmount += amount;
        }

        position.amount += amount; // this tracks both, token and fytoken position as you can see. 

        position.tokenAllocation += tokenAllocation; 
        idoConfig.idoTokensSold += tokenAllocation;

        // Update idoRound contribution tracker
        idoConfig.totalFunded[token] += amount;
        idoConfig.fundedUSDValue += amount;

        // Take token from transaction sender to smart contract 
        TokenTransfer._depositToken(token, msg.sender, amount);
        emit Participation(msg.sender, token, amount, tokenAllocation);
    }

    /**
        * @dev Checks all conditions for participation in an IDO. Reverts if any conditions are not met.
        * @param idoConfig The Config Params of the IDO.
        * @param idoClock The Clock Params of the IDO.
        * @param participant The address of the participant.
        * @param token The token used for participation.
        * @param amount The amount of the token.
        syntax on
    */
    function _basicParticipationCheck(IDOStructs.IDORoundConfig storage idoConfig, IDOStructs.IDORoundClock storage idoClock, address participant, address token, uint256 amount) internal view {

        // Cache storage variables used multiple times to memory
        address buyToken = idoConfig.buyToken;
        address fyToken = idoConfig.fyToken;

        // Check if the token is a valid participation token
        if (token != buyToken && token != fyToken) {
            revert InvalidParticipateToken(token);
        }

        // Ensure the participant is registered in the parent MetaIDO. Some rounds could be registerless. See flag.
        if (!idoClock.hasNoRegList) {
            uint32 parentMetaIdoId = idoClock.parentMetaIdoId;
            if (parentMetaIdoId == 0) revert NonExistantMetaIDO(); //Parent MetaIDO does not exist.
            if (!metaIDOs[parentMetaIdoId].isRegistered[participant]) revert ParticipantNotRegistered();
        }

        // Check fyToken contribution limits
        if (token == fyToken) {
            uint256 maxFyTokenFundingInIdoTokens = (idoConfig.idoSize * idoConfig.fyTokenMaxBasisPoints) / 10000;
            // convert maxFyTokenFundingInIdoTokens to the correct unit measure
            uint256 maxFyTokenFundingInFyTokens = (maxFyTokenFundingInIdoTokens * idoConfig.idoPrice) / 10**idoConfig.idoTokenDecimals;
            if (idoConfig.totalFunded[fyToken] + amount > maxFyTokenFundingInFyTokens) {
                revert FyTokenContributionExceedsLimit();
            }
        }
    }

    /**
        * @dev Retrieves the participant's rank and multiplier from the parent MetaIDO.
        * @param idoRoundId The ID of the IDO round.
        * @param participant The address of the participant.
        * @return participantRank The rank of the participant.
        * @return participantMultiplier The multiplier of the participant. The value is in integer.
        */
    function _getParticipantData(uint32 idoRoundId, address participant) internal view returns (uint16 participantRank, uint16 participantMultiplier) {
        uint32 parentMetaIdoId = idoRoundClocks[idoRoundId].parentMetaIdoId;
        participantRank = metaIDOs[parentMetaIdoId].userRank[participant];
        participantMultiplier = metaIDOs[parentMetaIdoId].userMaxAllocMult[participant];
    }



    /**
         * @notice Claim IDO tokens for a specific IDO.
         * @dev This function allows a staker to claim their allocated IDO tokens for the given IDO.
         * @param idoRoundId The ID of the IDO.
         * @param staker The address of the staker claiming the IDO tokens.
         * @custom:throws NotFinalized if the IDO round is not finalized
         * @custom:throws NotClaimable if the claim period hasn't started
         * @custom:throws AlreadyCanceled if the IDO round has been canceled
         * @custom:throws NoTokensToWithdraw if the staker has no tokens to claim
         */
    function claimFromRound(uint32 idoRoundId, address staker) external {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        IDOStructs.Position memory pos = ido.accountPositions[staker];
        
        if (!idoClock.isFinalized) revert NotFinalized();
        if (block.timestamp < idoClock.claimableTime) revert NotClaimable();
        if (idoClock.isCanceled) revert AlreadyCanceled();

        if (pos.amount == 0) revert NoTokensToWithdraw();

        uint256 alloc = pos.tokenAllocation; 
        address idoToken = ido.idoToken;

        globalTokenAllocPerIDORound[idoToken] -= alloc;
        ido.idoTokensClaimed += alloc;

        delete ido.accountPositions[staker];

        _depositToTreasury(idoRoundId, pos);

        TokenTransfer._transferToken(idoToken, staker, alloc);

        emit Claim(staker, alloc);
    }

    /**
         * @notice Withdraw excess IDO tokens from the contract.
         * @dev Allows the owner to withdraw excess IDO tokens from the contract. 
         *      Calculates spare tokens based on contract balance and global allocation.
         * @param idoRoundId The ID of the IDO from which tokens are withdrawn.
         * @custom:throws NoTokensToWithdraw if there are no excess tokens to withdraw
         */
    function withdrawSpareIDO(uint32 idoRoundId) external onlyOwner {
        address idoToken = idoRoundConfigs[idoRoundId].idoToken;

        uint256 contractBal = IERC20(idoToken).balanceOf(address(this));
        uint256 globalAllocation = globalTokenAllocPerIDORound[idoToken];

        uint256 spareTokens = contractBal - globalAllocation;
        if (spareTokens == 0) revert NoTokensToWithdraw();

        TokenTransfer._transferToken(idoToken, msg.sender, spareTokens);
        emit ExcessTokensWithdrawn(idoRoundId, idoToken, spareTokens);
    }

    // ======================================    
    // =============== REGISTER ==============
    // ======================================    

    function _registerUserForMetaIDO(uint32 metaIdoId, address user) internal returns (bool, uint16, uint16) {
        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];

        // Try-catch block to handle potential errors from external call
        try multiplierContract.getMultiplier(user) returns (uint256 multiplier, uint256 rank) {
            uint16 newRank = uint16(rank);
            uint16 newMultiplier = uint16(multiplier);

            // If user is already registered, only allow update if new rank is higher
            if (metaIDO.isRegistered[user]) {
                if (newRank <= metaIDO.userRank[user]) {
                    revert RegisterRankNotHigher(metaIDO.userRank[user], newRank);
                }
            }

            // Store user's rank and multiplier
            metaIDO.userRank[user] = newRank;
            metaIDO.userMaxAllocMult[user] = newMultiplier;
            metaIDO.isRegistered[user] = true;

            return (true, newRank, newMultiplier);

        } catch {
            return (false, 0, 0); // Failed to retrieve multiplier and rank
        }
    }

    /**
        * @notice Registers the sender in the specified MetaIDO if registration is open and stores or updates their rank and multiplier.
        * @dev Registers `msg.sender` to `metaIdoId` during the allowed registration period and records their current rank and multiplier.
        * If the user is already registered it reverts, it only updates if the new rank is higher.
        * @param metaIdoId The identifier of the MetaIDO to register for.
        */
    function registerForMetaIDO(uint32 metaIdoId) external {
        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        // Round does not exist or registration has been disabled for users
        if(metaIDO.registrationEndTime == metaIDO.registrationStartTime) revert RegistrationDisabledForUsers();
        if (block.timestamp < metaIDO.registrationStartTime) revert RegistrationNotStarted(); 
        if (block.timestamp > metaIDO.registrationEndTime) revert RegistrationEnded();

        (bool success, uint16 newRank, uint16 newMultiplier) = _registerUserForMetaIDO(metaIdoId, msg.sender);

        if (!success) revert FailedToRegisterUser();

        emit UserRegistered(metaIdoId, msg.sender, newRank, newMultiplier);
    }


    /**
        * @notice Registers multiple users to a MetaIDO regardless of the registration period, only callable by the contract owner. For gas efficiency, does not update ranks and multiplier if already registered.
        * @dev Allows batch registration of users by an admin for `metaIdoId`.
        * @param metaIdoId The identifier of the MetaIDO.
        * @param users An array of user addresses to register.
        */
    function adminAddRegForMetaIDO(uint32 metaIdoId, address[] calldata users) external onlyOwner {
        if (metaIdoId >= nextMetaIdoId) revert NonExistantMetaIDO(); //Trying to register users to an non existant MetaIDO.

        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        address[] memory newlyRegistered = new address[](users.length);
        uint16[] memory newRanks = new uint16[](users.length);
        uint16[] memory newMultipliers = new uint16[](users.length);

        uint count = 0;

        for (uint i = 0; i < users.length; i++) {
            address user = users[i];

            if (!metaIDO.isRegistered[user]) {
                (bool success, uint16 newRank, uint16 newMultiplier) = _registerUserForMetaIDO(metaIdoId, user);
                if (success) {
                    newlyRegistered[count] = user;
                    newRanks[count] = newRank;
                    newMultipliers[count] = newMultiplier;
                    count++;
                }
            }
        }

        if (count != users.length) {
            assembly {
                mstore(newlyRegistered, count)
                mstore(newRanks, count)
                mstore(newMultipliers, count)
            }
        }

        emit UsersAdminRegistered(metaIdoId, newlyRegistered, newRanks, newMultipliers);
    }

    /**
        * @notice Removes multiple users from a MetaIDO's registration list, only callable by the contract owner.
        * @dev Allows batch unregistration of users by an admin for `metaIdoId`.
        * @param metaIdoId The identifier of the MetaIDO.
        * @param users An array of user addresses to unregister.
        */
    function adminRemoveRegForMetaIDO(uint32 metaIdoId, address[] calldata users) external onlyOwner {
        if (metaIdoId >= nextMetaIdoId) revert NonExistantMetaIDO(); //Trying to remove users to an non existant MetaIDO.

        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        address[] memory removedUsers = new address[](users.length);
        uint count = 0;

        for (uint i = 0; i < users.length; i++) {
            address user = users[i];
            if (metaIDO.isRegistered[user]) {
                metaIDO.isRegistered[user] = false;
                delete metaIDO.userRank[user];
                delete metaIDO.userMaxAllocMult[user];
                removedUsers[count] = user;
                count++;
            }
        }

        if (count != users.length) {
            assembly {
                mstore(removedUsers, count)
            }
        }

        emit UsersAdminRemoved(metaIdoId, removedUsers);
    }

    // ======================================    
    // =============== METAIDO ==============
    // ======================================    

    /**
         * @notice Creates a new MetaIDO and returns its unique identifier
         * @dev Increments the internal counter to assign a new ID and ensures uniqueness
         * @param roundIds An array of IDO round IDs to associate with this MetaIDO
         * @param registrationStartTime The start time for registration.
         * @param registrationEndTime The end time for registration, also set as initialRegistrationEndTime.
         * @return metaIdoId The unique identifier for the newly created MetaIDO
         * @custom:throws Time1MustBeAfterTime2 if registrationEndTime is before registrationStartTime
         */
    function createMetaIDO(uint32[] calldata roundIds, uint64 registrationStartTime, uint64 registrationEndTime) external onlyOwner returns (uint32) {
        // inverterted the values in the check below for simplicity.
        // NOTE: Both times can be set to the same timestamp (this is a feature). Disabling user reg, but allowing admin reg.
        if (registrationEndTime < registrationStartTime) revert Time1MustBeAfterTime2(registrationEndTime, registrationStartTime);

        uint32 metaIdoId = nextMetaIdoId++;
        IDOStructs.MetaIDO storage newMetaIDO = metaIDOs[metaIdoId];
        newMetaIDO.registrationStartTime = registrationStartTime;
        newMetaIDO.registrationEndTime = registrationEndTime;
        newMetaIDO.initialRegistrationEndTime = registrationEndTime; // Initially set to the same as registrationEndTime

        // Add each round ID to the MetaIDO
        for (uint i = 0; i < roundIds.length; i++) {
            manageRoundToMetaIDO(metaIdoId, roundIds[i], true);
        }

        emit MetaIDOCreated(metaIdoId, registrationStartTime, registrationEndTime); // Emit an event for the creation

        return metaIdoId;
    }

    /**
        * @notice Manages (adds or removes) a round in a specified MetaIDO
        * @dev Adds a round to the MetaIDO if `addRound` is true, otherwise removes it
        * @param metaIdoId The identifier of the MetaIDO to manage
        * @param roundId The identifier of the round to be managed
        * @param addRound True to add the round to the MetaIDO, false to remove it
        */
    function manageRoundToMetaIDO(uint32 metaIdoId, uint32 roundId, bool addRound) public onlyOwner {
        if (metaIdoId >= nextMetaIdoId) revert NonExistantMetaIDO(); 
        if (idoRoundClocks[roundId].idoStartTime == 0) revert IDORoundNotInitialized(); // Check if the round exists

        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];

        if (addRound) {
            // Note: Registration can end after the IDO round starts.
            //"Registration must start before the IDO round begins."
            if (metaIDOs[metaIdoId].registrationStartTime >= idoRoundClocks[roundId].idoStartTime) revert RegMustStartBeforeIdoRoundBegins(); 
            //"IDO round already has a parent MetaIDO"
            if (idoRoundClocks[roundId].parentMetaIdoId != 0) revert ExistingMetaIDO(); 


            metaIDO.roundIds.push(roundId);
            idoRoundClocks[roundId].parentMetaIdoId = metaIdoId; 
            emit RoundAddedToMetaIDO(roundId, metaIdoId); 
        } else {
            uint32[] storage rounds = metaIDO.roundIds;
            bool found = false;
            for (uint i = 0; i < rounds.length; i++) {
                if (rounds[i] == roundId) {
                    found = true;
                    rounds[i] = rounds[rounds.length - 1];  
                    rounds.pop();  
                    break;
                }
            }
            if (found) {
                idoRoundClocks[roundId].parentMetaIdoId = 0; 
                emit RoundRemovedFromMetaIDO(roundId, metaIdoId); 
            } else {
                revert("Round not found in MetaIDO");
            }
        }
    }

    /**
        * @notice Delays the registration end time for a specific MetaIDO.
        * @dev Updates the registration end time for the given MetaIDO to a new time, provided the new time is later
    * than the current end time and does not exceed two weeks from the initial registration end time.
        * @param metaIdoId The ID of the MetaIDO to update.
        * @param newTime The new registration end time to set.
        */
    function delayMetaIDORegEndTime(uint32 metaIdoId, uint64 newTime) external onlyOwner {
        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];

        //"New registration end time must be after current end time"
        if (newTime <= metaIDO.registrationEndTime) revert NewTimeNotLaterThanCurrent();
        if (newTime > metaIDO.initialRegistrationEndTime + 2 weeks) revert NewTimeExceedsTwoWeeksLimit();

        emit MetaIDORegEndTimeDelayed(metaIdoId, metaIDO.registrationEndTime, newTime);

        metaIDO.registrationEndTime = newTime;
    }

    // =============================================================== 
    // =============== IDOSpecs & Multiplier  ========================
    // ===============================================================

    /**
        * @notice Sets the specifications for an IDO round.
        * @dev This function can only be called by the owner and must be set before enabling the IDO round.
        *      If noRank is true, there is no rank check.
        *      If noMultiplier is true, rank alloc multiplier is not applied.
        *      Sets the specsInitialized flag to true.
        * @param idoRoundId The ID of the IDO round to set specifications for.
        * @param minRank The minimum rank required to participate in this round.
        * @param maxRank The maximum rank allowed to participate in this round (inclusive).
        * @param maxAlloc The maximum amount a participant can contribute to the IDO in USD.
        * @param minAlloc The minimum amount a participant has to contribute to the IDO in USD (at least 1).
        * @param maxAllocMultiplier The multiplier to apply to allocations in this round (in basis points).
        * @param noMultiplier Whether to disable the rank alloc multiplier.
        * @param noRank Whether to disable rank checks for this round.
        * @param standardMaxAllocMult Whether to set maxAllocMultiplier to the 1x standard (10_000).
        */
    function setIDORoundSpecs(
        uint32 idoRoundId,
        uint16 minRank,
        uint16 maxRank,
        uint256 maxAlloc,
        uint256 minAlloc,
        uint16 maxAllocMultiplier,
        bool noMultiplier,
        bool noRank,
        bool standardMaxAllocMult
    ) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        if (idoClock.idoStartTime == 0) revert IDORoundNotInitialized();
        //"Cannot set specs for already enabled round"
        if (idoClock.isEnabled) revert IDORoundIsEnabled();
        //"Max rank must be greater than or equal to min rank"
        if (maxRank < minRank) revert MaxRankLessThanMinRank();
        //"Max allocation must be greater than or equal to min allocation"
        if (maxAlloc < minAlloc) revert MaxAllocLessThanMinAlloc();
        //"Minimum allocation must be at least 1"
        if (minAlloc == 0) minAlloc = 1;

        uint16 finalMaxAllocMultiplier = standardMaxAllocMult ? 10_000 : maxAllocMultiplier;

        idoRoundSpecs[idoRoundId] = IDOStructs.IDORoundSpec({
            minRank: minRank,
            maxRank: maxRank,
            maxAlloc: maxAlloc,
            minAlloc: minAlloc,
            maxAllocMultiplier: finalMaxAllocMultiplier,
            noMultiplier: noMultiplier,
            noRank: noRank,
            specsInitialized: true
        });

        emit IDORoundSpecsSet(idoRoundId, minRank, maxRank, maxAlloc, minAlloc, maxAllocMultiplier, noMultiplier, noRank);
    }

    /**
        * @notice Checks participation eligibility based on round specifications and calculates the maximum allocated amount.
        * @dev This function performs checks based on the IDO round specifications, including rank eligibility
    *      and allocation limits. It calculates and checks against the maximum effective allocated amount 
    *      considering any applicable multipliers.
        * @param idoRoundId The ID of the IDO round being participated in.
        * @param participant The address of the participant.
        * @param amount The amount the participant is attempting to contribute.
        * @param participantRank The rank of the participant, queried externally before calling this function.
        * @param participantMultiplier The multiplier of the participant, queried externally before calling this function. Value is in integer. 1x,2x,3x,...
        * @custom:throws "Participant's rank is not eligible for this IDO round" if the participant's rank is outside the allowed range.
        * @custom:throws "Contribution below minimum allocation amount" if the contribution is less than the minimum allowed.
        * @custom:throws "Contribution exceeds maximum allocation amount" if the total contribution is more than the maximum allowed.
        */
    function _roundSpecsParticipationCheck(
        uint32 idoRoundId, 
        address participant, 
        uint256 amount,
        uint16 participantRank,
        uint16 participantMultiplier
    ) internal view {
        IDOStructs.IDORoundSpec storage idoSpec = idoRoundSpecs[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        // Check rank eligibility
        bool noRank = idoSpec.noRank;
        if (!noRank) {
            uint16 minRank = idoSpec.minRank;
            uint16 maxRank = idoSpec.maxRank;

            if (participantRank < minRank || participantRank > maxRank) {
            revert ParticipantRankNotEligible(participantRank, minRank, maxRank);
            }
        }

        // Check and calculate allocation
        //"Contribution below minimum allocation amount"
        if (amount < idoSpec.minAlloc) revert ContributionBelowMinAlloc(amount, idoSpec.minAlloc);
        uint256 totalContribution = idoConfig.accountPositions[participant].amount + amount;

        uint256 maxAlloc = idoSpec.maxAlloc; // For clarity. Could have used value below.
        uint256 maxAllocatedAmount = maxAlloc;

        if (!idoSpec.noMultiplier) {
            uint256 maxAllocMultiplier = idoSpec.maxAllocMultiplier;
            maxAllocatedAmount = (maxAlloc * participantMultiplier * maxAllocMultiplier) / 10000;
            if(noRank && participantRank == 0) {
                maxAllocatedAmount = (maxAlloc * 1 * maxAllocMultiplier) / 10000;
            }
        } 

        //"Contribution exceeds maximum allocation amount"
        if (totalContribution > maxAllocatedAmount) revert ContributionTotalAboveMaxAlloc(totalContribution, maxAllocatedAmount);
    }

    /**
        * @notice Proposes an update to the multiplier contract address.
        * @dev Initiates a timelock for updating the multiplier contract. Can only be called by the owner.
        * @param _newMultiplierContract The address of the proposed new multiplier contract.
        * @custom:throws "Invalid multiplier contract address" if the proposed address is zero.
        * @custom:throws "There is already a pending multiplier contract update" if there's an ongoing proposal.
        */
    function proposeMultiplierContractUpdate(address _newMultiplierContract) external onlyOwner {
        if(_newMultiplierContract == address(0)) revert newMultiplierIsZeroAddress();
        
        //"There is already a pending multiplier contract update"
        if(proposedMultiplierContract != address(0)) revert updatePending(multiplierContractUpdateUnlockTime); 

        proposedMultiplierContract = _newMultiplierContract;
        multiplierContractUpdateUnlockTime = block.timestamp + MULTIPLIER_UPDATE_DELAY;

        emit MultiplierContractUpdateProposed(_newMultiplierContract, multiplierContractUpdateUnlockTime);
    }

    /**
        * @notice Executes the proposed update to the multiplier contract.
        * @dev Finalizes the multiplier contract update after the timelock period. Can only be called by the owner.
        * @custom:throws "No multiplier contract update proposed" if there's no pending proposal.
        * @custom:throws "Multiplier contract update is still locked" if the timelock period hasn't elapsed.
        */
    function executeMultiplierContractUpdate() external onlyOwner {
        //"No multiplier contract update proposed"
        if (proposedMultiplierContract == address(0)) revert updatePending(0);
        //"Multiplier contract update is still locked"
        if (block.timestamp < multiplierContractUpdateUnlockTime) revert updatePending(multiplierContractUpdateUnlockTime);

        address oldContract = address(multiplierContract);
        multiplierContract = IMultiplierContract(proposedMultiplierContract);

        proposedMultiplierContract = address(0); // Reset the proposed address
        emit MultiplierContractUpdated(oldContract, address(multiplierContract));
    }
}


