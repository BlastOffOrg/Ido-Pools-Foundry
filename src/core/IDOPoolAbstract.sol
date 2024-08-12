// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interface/IIDOPool.sol";
import "../lib/TokenTransfer.sol";
import "./IDOStorage.sol";
import "./IDOPoolView.sol";

abstract contract IDOPoolAbstract is IIDOPool, Ownable2StepUpgradeable, IDOStorage, IDOPoolView {
    using IDOStructs for *;
    // Make the structs available in the global namespace


    modifier notFinalized(uint32 idoRoundId) {
        if (idoRoundClocks[idoRoundId].isFinalized) revert AlreadyFinalized();
        _;
    }

    modifier finalized(uint32 idoRoundId) {
        if (!idoRoundClocks[idoRoundId].isFinalized) revert NotFinalized();
        _;
    }

    modifier enabled(uint32 idoRoundId) {
        if (!idoRoundClocks[idoRoundId].isEnabled) revert NotEnabled();
        _;
    }

    modifier canceled(uint32 idoRoundId) {
        if (!idoRoundClocks[idoRoundId].isCanceled) revert NotCanceled();
        _;
    }

    modifier afterStart(uint32 idoRoundId) {
        if(block.timestamp < idoRoundClocks[idoRoundId].idoStartTime) revert NotStarted();
        _;
    }

    modifier claimable(uint32 idoRoundId) {
        if (!idoRoundClocks[idoRoundId].isFinalized) revert NotFinalized();
        if (block.timestamp < idoRoundClocks[idoRoundId].claimableTime) revert NotClaimable();
        _;
    }

    function __IDOPoolAbstract_init(address treasury_, address _multiplierContract) internal onlyInitializing {
        treasury = treasury_;
        multiplierContract = IMultiplierContract(_multiplierContract);
        __Ownable2Step_init();
    }

    // ============================================= 
    // =============== Owner IDORound ==============
    // =============================================



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
        require(idoEndTime > idoStartTime, "End time must be after start time");
        require(claimableTime > idoEndTime, "Claim time must be after end time");
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
        config.minimumFundingGoal = minimumFundingGoal;
        config.fyTokenMaxBasisPoints = fyTokenMaxBasisPoints;
        config.fundedUSDValue = 0;

        emit IDOCreated(idoRoundId, idoName, idoToken, idoPrice, idoSize, minimumFundingGoal, idoStartTime, idoEndTime, claimableTime);
    }

    /**
        * @notice Finalize the IDO pool for a specific IDO.
        * @dev This function finalizes the given IDO, calculates the total value of USD funded, and determines the IDO size.
        * It cannot be finalized if the IDO has not reached its end time or the minimum funding goal is not met.
        * It also reduces the global token allocation by the amount of unsold tokens.
        * @param idoRoundId The ID of the IDO to finalize.
        */
    function finalizeRound(uint32 idoRoundId) external onlyOwner notFinalized(idoRoundId) {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        if (block.timestamp < idoClock.idoEndTime) revert IDONotEnded();
        if (idoConfig.fundedUSDValue < idoConfig.minimumFundingGoal) revert FudingGoalNotReached();

        idoClock.isFinalized = true;
        // Reduce global token allocation by the unsold tokens
        uint256 unsoldTokens = idoConfig.idoSize - idoConfig.idoTokensSold;
        globalTokenAllocPerIDORound[idoConfig.idoToken] -= unsoldTokens;

        emit Finalized(idoRoundId,idoConfig.fundedUSDValue, idoConfig.idoTokensSold, idoConfig.idoSize);
    }

    /**
        * @notice Cancels an IDO round. This can only be done by the owner, and allows participants to claim refunds.
        * @dev Sets the `isCanceled` flag and prevents further participation or finalization.
        * @param idoRoundId The ID of the IDO to cancel.
        */
    function cancelIDORound(uint32 idoRoundId) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        require(!idoClock.isCanceled, "IDO already canceled");
        idoClock.isCanceled = true;

        // Reduce global token allocation if the round was previously enabled
        if (idoClock.isEnabled) {
            globalTokenAllocPerIDORound[idoConfig.idoToken] -= idoConfig.idoSize;
        }

        emit IDOCanceled(idoRoundId, idoConfig.fundedUSDValue, idoConfig.idoTokensSold, idoConfig.idoSize); 
    }

    /**
        * @notice This function enables an IDO round if it meets all requirements, including sufficient token reserves across all rounds.
        * @dev Only callable by the owner. Ensures tokens for this and all other enabled rounds do not exceed the token balance.
        * @param idoRoundId The identifier of the IDO round to enable.
        */
    function enableIDORound(uint32 idoRoundId) external onlyOwner notFinalized(idoRoundId) {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDOStructs.IDORoundSpec storage idoSpec = idoRoundSpecs[idoRoundId];

        require(!idoClock.isEnabled, "IDO round already enabled");
        require(idoClock.idoStartTime != 0, "IDO round not properly initialized");
        require(!idoClock.isCanceled, "IDO round is canceled");
        require(idoSpec.specsInitialized, "IDO round specs not set");

        // Calculate new total allocation for this token, including already allocated tokens
        uint256 newTotalAllocation = globalTokenAllocPerIDORound[idoConfig.idoToken] + idoConfig.idoSize;

        // Checking the token balance in the contract for the IDO token
        uint256 tokenBalance = IERC20(idoConfig.idoToken).balanceOf(address(this));
        require(tokenBalance >= newTotalAllocation, "Insufficient tokens in contract for all enabled IDOs");

        // Update global token allocation
        globalTokenAllocPerIDORound[idoConfig.idoToken] = newTotalAllocation;

        // Enable the round
        idoClock.isEnabled = true;

        emit IDOEnabled(idoRoundId, idoConfig.idoToken, idoConfig.idoSize, newTotalAllocation, tokenBalance);

    }

    /**
        * @notice Enables the no registration list requirement for a specific IDO round if it's not already enabled.
        * @dev Sets `hasNoRegList` to true for the specified IDO round, indicating that participants do not need to be registered.
        *      Can only be set once.
        * @param idoRoundId The identifier of the IDO round to modify.
        */
    function enableHasNoRegList(uint32 idoRoundId) external onlyOwner {
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];

        // Disabled: Can be set anytime.
        //require(block.timestamp < idoClock.idoStartTime, "Cannot enable hasNoRegList after IDO has started.");

        require(!idoClock.hasNoRegList, "hasNoRegList is already enabled.");

        idoClock.hasNoRegList = true;

        emit HasNoRegListEnabled(idoRoundId);
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
        require(newFyTokenMaxBasisPoints <= 10000, "Basis points cannot exceed 10000");
        require(block.timestamp < idoClock.idoStartTime, "Cannot change settings after IDO start");

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
        require(_newTime > ido.initialClaimableTime, "New claimable time must be after current claimable time");
        require(_newTime > ido.idoEndTime, "New claimable time must be after current ido time");
        require(
            _newTime <= ido.initialClaimableTime + 2 weeks, "New claimable time exceeds 2 weeks from initial claimable time"
        );
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
        require(_newTime > ido.initialIdoEndTime, "New IDO end time must be after initial IDO end time");
        require(_newTime <= ido.initialIdoEndTime + 2 weeks, "New IDO end time exceeds 2 weeks from initial IDO end time");
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
    function claimRefund(uint32 idoRoundId) external canceled(idoRoundId){
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDOStructs.Position storage pos = idoConfig.accountPositions[msg.sender];

        require(pos.amount > 0, "No funds to refund");

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
        if (pos.fyAmount > 0) TokenTransfer._transferToken(ido.fyToken, treasury, pos.fyAmount);
        if (pos.amount - pos.fyAmount > 0) TokenTransfer._transferToken(ido.buyToken, treasury, pos.amount - pos.fyAmount);
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
    ) external payable notFinalized(idoRoundId) enabled(idoRoundId) afterStart(idoRoundId) {
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        _basicParticipationCheck(idoRoundId, msg.sender, token, amount); // Standard participation checks

        (uint16 participantRank, uint16 participantMultiplier) = _getParticipantData(idoRoundId, msg.sender);

        _roundSpecsParticipationCheck(idoRoundId, msg.sender, amount, participantRank, participantMultiplier);     // Round specs check

        IDOStructs.Position storage position = idoConfig.accountPositions[msg.sender];

        if (token == idoConfig.fyToken) {
            position.fyAmount += amount;
        }

        position.amount += amount; // this tracks both, token and fytoken position as you can see. 

        // Calculate token allocation here based on current contribution
        uint256 tokenAllocation = (amount * 10**idoConfig.idoTokenDecimals) / idoConfig.idoPrice;
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
        * @param idoRoundId The ID of the IDO.
        * @param participant The address of the participant.
        * @param token The token used for participation.
        * @param amount The amount of the token.
        syntax on
    */
    function _basicParticipationCheck(uint32 idoRoundId, address participant, address token, uint256 amount) internal view {
        IDOStructs.IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDOStructs.IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];

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
            require(parentMetaIdoId != 0, "No parent MetaIDO associated with this round.");
            require(metaIDOs[parentMetaIdoId].isRegistered[participant], "Participant is not registered for the parent MetaIDO.");
        }

        // Perform calculations after cheaper checks have passed
        uint256 globalTotalFunded = idoConfig.totalFunded[buyToken] + idoConfig.totalFunded[fyToken] + amount;

        // Check fyToken contribution limits
        if (token == fyToken) {
            uint256 maxFyTokenFunding = (idoConfig.idoSize * idoConfig.fyTokenMaxBasisPoints) / 10000;
            require(globalTotalFunded <= maxFyTokenFunding, "fyToken contribution exceeds limit");
        }

        // Check funding cap overflow
        uint256 additionalUSD = amount * idoConfig.idoPrice;
        uint256 newFundedUSDValue = idoConfig.fundedUSDValue + additionalUSD;
        require(newFundedUSDValue <= idoConfig.idoSize * idoConfig.idoPrice, "Funding cap exceeded");

    }

    /**
        * @dev Retrieves the participant's rank and multiplier from the parent MetaIDO.
        * @param idoRoundId The ID of the IDO round.
        * @param participant The address of the participant.
        * @return participantRank The rank of the participant.
        * @return participantMultiplier The multiplier of the participant.
        */
    function _getParticipantData(uint32 idoRoundId, address participant) internal view returns (uint16 participantRank, uint16 participantMultiplier) {
        uint32 parentMetaIdoId = idoRoundClocks[idoRoundId].parentMetaIdoId;
        participantRank = metaIDOs[parentMetaIdoId].userRank[participant];
        participantMultiplier = metaIDOs[parentMetaIdoId].userMaxAllocMult[participant];
    }



    /**
        * @notice Claim refund and IDO tokens for a specific IDO.
        * @dev This function allows a staker to claim their allocated IDO tokens for the given IDO.
        * @param idoRoundId The ID of the IDO.
        * @param staker The address of the staker claiming the IDO tokens.
        */

    function claimFromRound(uint32 idoRoundId, address staker) external claimable(idoRoundId) {
        IDOStructs.IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        IDOStructs.Position memory pos = ido.accountPositions[staker];
        if (pos.amount == 0) revert NoStaking();

        uint256 alloc = pos.tokenAllocation; 

        globalTokenAllocPerIDORound[ido.idoToken] -= alloc;

        delete ido.accountPositions[staker];

        _depositToTreasury(idoRoundId, pos);

        TokenTransfer._transferToken(ido.idoToken, staker, alloc);

        emit Claim(staker, alloc);
    }

    /**
        * @notice Withdraw remaining unsold IDO tokens after the round is finalized.
        * @dev Allows the owner to withdraw unsold IDO tokens from a finalized round. Ensures that only spare tokens are withdrawn.
        * @param idoRoundId The ID of the IDO from which tokens are withdrawn.
        */
    function withdrawSpareIDO(uint32 idoRoundId) external finalized(idoRoundId) onlyOwner {
        IDOStructs.IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        uint256 contractBal = IERC20(ido.idoToken).balanceOf(address(this));
        require(contractBal >= ido.idoSize, "Contract token balance less than expected IDO size");

        uint256 spare = ido.idoSize - ido.idoTokensSold;
        require(spare > 0, "No spare tokens to withdraw");

        TokenTransfer._transferToken(ido.idoToken, msg.sender, spare);
    }

    // ======================================    
    // =============== REGISTER ==============
    // ======================================    

    /**
        * @notice Registers the sender in the specified MetaIDO if registration is open and stores or updates their rank and multiplier.
        * @dev Registers `msg.sender` to `metaIdoId` during the allowed registration period and records their current rank and multiplier.
        * If the user is already registered it reverts, it only updates if the new rank is higher.
        * @param metaIdoId The identifier of the MetaIDO to register for.
        */
    function registerForMetaIDO(uint32 metaIdoId) external {
        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        require(metaIDO.registrationEndTime != metaIDO.registrationStartTime, "Registration disabled for users");
        require(block.timestamp >= metaIDO.registrationStartTime, "Registration has not started yet");
        require(block.timestamp <= metaIDO.registrationEndTime, "Registration has ended");
        require(!metaIDO.isRegistered[msg.sender], "User already registered");


        // Try-catch block to handle potential errors from external call
        try multiplierContract.getMultiplier(msg.sender) returns (uint256 multiplier, uint256 rank) {
            uint16 newRank = uint16(rank);
            uint16 newMultiplier = uint16(multiplier);

            // If user is already registered, only allow update if new rank is higher
            if (metaIDO.isRegistered[msg.sender]) {
                require(newRank > metaIDO.userRank[msg.sender], "New rank must be higher than current rank");
            }

            // Store user's rank and multiplier
            metaIDO.userRank[msg.sender] = newRank;
            metaIDO.userMaxAllocMult[msg.sender] = newMultiplier;
            metaIDO.isRegistered[msg.sender] = true;

            emit UserRegistered(metaIdoId, msg.sender, newRank, newMultiplier);
        } catch {
            // Handle the error (e.g., revert with a message)
            revert("Failed to retrieve user multiplier and rank");
        }
    }


    /**
        * @notice Registers multiple users to a MetaIDO regardless of the registration period, only callable by the contract owner.
        * @dev Allows batch registration of users by an admin for `metaIdoId`.
        * @param metaIdoId The identifier of the MetaIDO.
        * @param users An array of user addresses to register.
        */
    function adminAddRegForMetaIDO(uint32 metaIdoId, address[] calldata users) external onlyOwner {
        require(metaIdoId < nextMetaIdoId, "MetaIDO does not exist");

        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        address[] memory newlyRegistered = new address[](users.length);
        uint count = 0;

        for (uint i = 0; i < users.length; i++) {
            address user = users[i];

            if (!metaIDO.isRegistered[user]) {
                metaIDO.isRegistered[user] = true;
                newlyRegistered[count++] = user;
            }
        }

        if (count != users.length) {
            assembly {
                mstore(newlyRegistered, count)
            }
        }

        emit UsersAdminRegistered(metaIdoId, newlyRegistered);
    }

    /**
        * @notice Removes multiple users from a MetaIDO's registration list, only callable by the contract owner.
        * @dev Allows batch unregistration of users by an admin for `metaIdoId`.
        * @param metaIdoId The identifier of the MetaIDO.
        * @param users An array of user addresses to unregister.
        */
    function adminRemoveRegForMetaIDO(uint32 metaIdoId, address[] calldata users) external onlyOwner {
        require(metaIdoId < nextMetaIdoId, "MetaIDO does not exist");

        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        address[] memory removedUsers = new address[](users.length);
        uint count = 0;

        for (uint i = 0; i < users.length; i++) {
            address user = users[i];
            if (metaIDO.isRegistered[user]) {
                metaIDO.isRegistered[user] = false;
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
        * @param registrationStartTime The start time for registration.
        * @param registrationEndTime The end time for registration, also set as initialRegistrationEndTime.
        * @return metaIdoId The unique identifier for the newly created MetaIDO
        */
    function createMetaIDO(uint32[] calldata roundIds, uint64 registrationStartTime, uint64 registrationEndTime) external onlyOwner returns (uint32) {
        require(registrationEndTime >= registrationStartTime, "End time must be equal or after start time");

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
        require(metaIdoId < nextMetaIdoId, "MetaIDO does not exist");  // Ensure the MetaIDO exists
        require(idoRoundClocks[roundId].idoStartTime != 0, "IDO round does not exist");  // Check if the round exists

        IDOStructs.MetaIDO storage metaIDO = metaIDOs[metaIdoId];

        if (addRound) {
            require(metaIDOs[metaIdoId].registrationStartTime < idoRoundClocks[roundId].idoStartTime, "Registration must start before the IDO round begins.");
            // Note: Registration can end after the IDO round starts.

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
        require(newTime > metaIDO.registrationEndTime, "New registration end time must be after current end time");
        require(newTime <= metaIDO.initialRegistrationEndTime + 2 weeks, "New registration end time exceeds 2 weeks from initial end time");

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
        require(idoClock.idoStartTime != 0, "IDO round not properly initialized");
        require(!idoClock.isEnabled, "Cannot set specs for already enabled round");
        require(maxRank >= minRank, "Max rank must be greater than or equal to min rank");
        require(maxAlloc >= minAlloc, "Max allocation must be greater than or equal to min allocation");
        require(minAlloc >= 1, "Minimum allocation must be at least 1");

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
        * @param participantMultiplier The multiplier of the participant, queried externally before calling this function.
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
        if (!idoSpec.noRank) {
            require(participantRank >= idoSpec.minRank && participantRank <= idoSpec.maxRank, "Participant's rank is not eligible for this IDO round");
        }

        // Check and calculate allocation
        require(amount >= idoSpec.minAlloc, "Contribution below minimum allocation amount");

        uint256 totalContribution = idoConfig.accountPositions[participant].amount + amount;

        uint256 maxAllocatedAmount;

        if (!idoSpec.noMultiplier) {
            maxAllocatedAmount = (idoSpec.maxAlloc * participantMultiplier * idoSpec.maxAllocMultiplier) / 10000;
        } else {
            maxAllocatedAmount = idoSpec.maxAlloc;
        }

        require(totalContribution <= maxAllocatedAmount, "Contribution exceeds maximum allocation amount");

    }

    /**
        * @notice Proposes an update to the multiplier contract address.
        * @dev Initiates a timelock for updating the multiplier contract. Can only be called by the owner.
        * @param _newMultiplierContract The address of the proposed new multiplier contract.
        * @custom:throws "Invalid multiplier contract address" if the proposed address is zero.
        * @custom:throws "New address is the same as current" if the proposed address is the same as the current one.
        * @custom:throws "There is already a pending multiplier contract update" if there's an ongoing proposal.
        */
    function proposeMultiplierContractUpdate(address _newMultiplierContract) external onlyOwner {
        require(_newMultiplierContract != address(0), "Invalid multiplier contract address");
        require(_newMultiplierContract != address(multiplierContract), "New address is the same as current");
        require(proposedMultiplierContract == address(0), "There is already a pending multiplier contract update");

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
        require(proposedMultiplierContract != address(0), "No multiplier contract update proposed");
        require(block.timestamp >= multiplierContractUpdateUnlockTime, "Multiplier contract update is still locked");

        address oldContract = address(multiplierContract);
        multiplierContract = IMultiplierContract(proposedMultiplierContract);

        proposedMultiplierContract = address(0); // Reset the proposed address
        emit MultiplierContractUpdated(oldContract, address(multiplierContract));
    }
}


