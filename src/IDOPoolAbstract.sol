// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "./interface/IIDOPool.sol";
import "./lib/TokenTransfer.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

abstract contract IDOPoolAbstract is IIDOPool, Ownable2StepUpgradeable {
    address public treasury;

    struct Position {
        uint256 amount; // Total amount funded
        uint256 fyAmount; // Amount funded in fyToken
        uint256 tokenAllocation;
    }

    struct IDORoundClock {
        uint64 idoStartTime;
        uint64 claimableTime;
        uint64 initialClaimableTime;
        uint64 idoEndTime;
        uint64 initialIdoEndTime;
        bool isFinalized;
        bool isCanceled;
        bool isEnabled;
        bool hasWhitelist; 
        bool hasNoRegList;
        uint32 parentMetaIdoId;
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
        uint256 minimumFundingGoal;
        uint256 fundedUSDValue;
        mapping(address => bool) whitelist;
        mapping(address => uint256) totalFunded;
        mapping(address => Position) accountPositions;
    }

    mapping(uint32 => IDORoundClock) public idoRoundClocks;
    mapping(uint32 => IDORoundConfig) public idoRoundConfigs;

    uint32 public nextIdoRoundId = 1;

    struct MetaIDO {
        uint32[] roundIds; 
        uint64 registrationStartTime;
        uint64 initialRegistrationEndTime;
        uint64 registrationEndTime;
        mapping(address => bool) isRegistered;
    }

    mapping(uint32 => MetaIDO) public metaIDOs;
    uint32 public nextMetaIdoId = 1; 

    mapping(address => uint256) public globalTokenAllocPerIDORound;

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

    function __IDOPoolAbstract_init(address treasury_) internal onlyInitializing {
        treasury = treasury_;
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
        idoRoundClocks[idoRoundId] = IDORoundClock({
            parentMetaIdoId: 0,
            idoStartTime: idoStartTime,
            claimableTime: claimableTime,
            initialClaimableTime: claimableTime,
            idoEndTime: idoEndTime,
            initialIdoEndTime: idoEndTime,
            isFinalized: false,
            isCanceled: false,
            isEnabled: false,
            hasNoRegList: false,
            hasWhitelist: false
        });

        //IDORoundConfig needs to be assigned like this, Nested mapping error.
        IDORoundConfig storage config = idoRoundConfigs[idoRoundId];
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
        * @param idoRoundId The ID of the IDO to finalize.
        */
    function finalizeRound(uint32 idoRoundId) external onlyOwner notFinalized(idoRoundId) {
        IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

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
        IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

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
        IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        require(!idoClock.isEnabled, "IDO round already enabled");
        require(idoClock.idoStartTime != 0, "IDO round not properly initialized");
        require(!idoClock.isCanceled, "IDO round is canceled");

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
        IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];

        // Disabled: Can be set anytime.
        //require(block.timestamp < idoClock.idoStartTime, "Cannot enable hasNoRegList after IDO has started.");
        
        require(!idoClock.hasNoRegList, "hasNoRegList is already enabled.");

        idoClock.hasNoRegList = true;

        emit HasNoRegListEnabled(idoRoundId);
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
        IDORoundClock storage ido = idoRoundClocks[idoRoundId];
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
        IDORoundClock storage ido = idoRoundClocks[idoRoundId];
        require(_newTime > ido.initialIdoEndTime, "New IDO end time must be after initial IDO end time");
        require(_newTime <= ido.initialIdoEndTime + 2 weeks, "New IDO end time exceeds 2 weeks from initial IDO end time");
        emit IdoEndTimeDelayed(ido.idoEndTime, _newTime);


        ido.idoEndTime = _newTime;
    }


    // =================================================== 
    // =============== Participant IDORound ==============
    // ===================================================


    function claimRefund(uint32 idoRoundId) external canceled(idoRoundId){
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        Position storage pos = idoConfig.accountPositions[msg.sender];

        require(pos.amount > 0, "No funds to refund");

        uint256 refundAmountFyToken = pos.fyAmount;
        uint256 refundAmountBuyToken = pos.amount - refundAmountFyToken;

        idoConfig.idoTokensSold -= pos.tokenAllocation;
        idoConfig.fundedUSDValue -= pos.amount; 

        if (refundAmountFyToken > 0) {
            idoConfig.totalFunded[idoConfig.fyToken] -= refundAmountFyToken;
            TokenTransfer._transferToken(idoConfig.fyToken, msg.sender, refundAmountFyToken);
        }

        if (refundAmountBuyToken > 0) {
            idoConfig.totalFunded[idoConfig.buyToken] -= refundAmountBuyToken;
            TokenTransfer._transferToken(idoConfig.buyToken, msg.sender, refundAmountBuyToken);
        }

        delete idoConfig.accountPositions[msg.sender]; 

        emit RefundClaim(idoRoundId, msg.sender, pos.amount, pos.fyAmount);
    }


    /**
        * @notice Transfer the staker's funds to the treasury for a specific IDO.
        * @dev This function transfers the staker's funds to the treasury.
        * @param idoRoundId The ID of the IDO.
        * @param pos The position of the staker.
        */
    function _depositToTreasury(uint32 idoRoundId, Position memory pos) internal {
        IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        TokenTransfer._transferToken(ido.fyToken, treasury, pos.fyAmount);
        TokenTransfer._transferToken(ido.buyToken, treasury, pos.amount - pos.fyAmount);
    }


    /**
        * @notice Participate in a specific IDO.
        * @dev This function allows a user to participate in a given IDO by contributing a specified amount of tokens.
        * @dev Checks have been delegated to the `_participationCheck` function.
        * @dev The token used for participation must be either the buyToken or fyToken of the IDO.
        * @param idoRoundId The ID of the IDO to participate in.
        * @param token The address of the token used to participate, must be either the buyToken or fyToken.
        * @param amount The amount of the token to participate with.
        */ 
    function participateInRound(
        uint32 idoRoundId, 
        address token, 
        uint256 amount
    ) external payable notFinalized(idoRoundId) enabled(idoRoundId) afterStart(idoRoundId) {
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        // Delegate call to external contract to get the multiplier
        //uint256 multiplier = delegateToCalculator(msg.sender); // TODO MULTIPLIER
        //uint256 effectiveAmount = amount * multiplier; // TODO MULTIPLIER

        _participationCheck(idoRoundId, msg.sender, token, amount); // Perform all participation checks
        // TODO multiplier amount position calculator and idoSize to tokens in smart contract calculator. see if enough tokens are even in the smart contract or prevent particpation
        Position storage position = idoConfig.accountPositions[msg.sender];

        if (token == idoConfig.fyToken) {
            position.fyAmount += amount;
        }

        position.amount += amount; // this tracks both, token and fytoken position as you can see. 

        // TODO MULTIPLIER New storage variable to track effective contribution
        //position.effectiveAmount += effectiveAmount; 

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
        * @dev Checks all conditions for participation in an IDO, including whitelist validation if required. Reverts if any conditions are not met.
        * @param idoRoundId The ID of the IDO.
        * @param participant The address of the participant.
        * @param token The token used for participation.
        * @param amount The amount of the token.
        syntax on
    */


    function _participationCheck(uint32 idoRoundId, address participant, address token, uint256 amount) internal view {
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];

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
        // Check whitelisting if enabled for this IDO
        if (idoClock.hasWhitelist && !idoConfig.whitelist[participant]) {
            revert("Recipient not whitelisted");
        }

        // Perform calculations after cheaper checks have passed
        uint256 globalTotalFunded = idoConfig.totalFunded[buyToken] + idoConfig.totalFunded[fyToken] + amount;

        // Check fyToken contribution limits
        if (token == fyToken) {
            uint256 maxFyTokenFunding = (idoConfig.idoSize * idoConfig.fyTokenMaxBasisPoints) / 10000;
            require(globalTotalFunded <= maxFyTokenFunding, "fyToken contribution exceeds limit");
        }

        _checkFundingCap(idoRoundId, amount);
    }

    /**
        * @dev Checks whether the IDO round's funding cap will be exceeded with the proposed contribution.
        * @param idoRoundId The identifier of the IDO round to check.
        * @param amount The amount of tokens being contributed.
        */
    function _checkFundingCap(uint32 idoRoundId, uint256 amount) internal view {
        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];

        // Calculate the additional USD based on the amount and the token price from the IDO configuration
        uint256 additionalUSD = amount * idoConfig.idoPrice;
        uint256 newFundedUSDValue = idoConfig.fundedUSDValue + additionalUSD;

        // Ensure the new funded USD value does not exceed the planned IDO size times the IDO price
        require(newFundedUSDValue <= idoConfig.idoSize * idoConfig.idoPrice, "Funding cap exceeded");
    }

    /**
        * @notice Claim refund and IDO tokens for a specific IDO.
        * @dev This function allows a staker to claim their allocated IDO tokens for the given IDO.
        * @param idoRoundId The ID of the IDO.
        * @param staker The address of the staker claiming the IDO tokens.
        */

    function claimFromRound(uint32 idoRoundId, address staker) external claimable(idoRoundId) {
        IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        Position memory pos = ido.accountPositions[staker];
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
        IDORoundConfig storage ido = idoRoundConfigs[idoRoundId];
        uint256 contractBal = IERC20(ido.idoToken).balanceOf(address(this));
        require(contractBal >= ido.idoSize, "Contract token balance less than expected IDO size");

        uint256 spare = ido.idoSize - ido.idoTokensSold;
        require(spare > 0, "No spare tokens to withdraw");

        TokenTransfer._transferToken(ido.idoToken, msg.sender, spare);
    }

    /**
        * @notice Modifies the whitelist status for a list of participants for a specific IDO.
        * @dev Adds or removes addresses from the whitelist mapping in the IDORoundConfig for the specified IDO, based on the flag.
        * @param idoRoundId The ID of the IDO.
        * @param participants The array of addresses of the participants to modify.
        * @param addToWhitelist True to add to the whitelist, false to remove from the whitelist.
        */
    function modifyWhitelist(uint32 idoRoundId, address[] calldata participants, bool addToWhitelist) external onlyOwner {
        require(idoRoundClocks[idoRoundId].hasWhitelist, "Whitelist not enabled for this IDO.");
        require(participants.length > 0, "Participant list cannot be empty.");

        for (uint i = 0; i < participants.length; i++) {
            idoRoundConfigs[idoRoundId].whitelist[participants[i]] = addToWhitelist;
        }
    }

    /**
        * @notice Sets the whitelist status for a specific IDO.
        * @dev Enables or disables the whitelist for an IDO. Whitelisting cannot be enabled once the IDO has started.
        *      Disabling can occur at any time unless the IDO is finalized or the whitelist is already disabled.
        *      Can only be called by the owner.
        * @param idoRoundId The ID of the IDO.
        * @param status True to enable the whitelist, false to disable it.
        */
    function setWhitelistStatus(uint32 idoRoundId, bool status) external onlyOwner {
        if (status) {
            require(block.timestamp < idoRoundClocks[idoRoundId].idoStartTime, "Cannot enable whitelist after IDO start.");
        } else {
            require(!idoRoundClocks[idoRoundId].isFinalized, "IDO is already finalized.");
            require(idoRoundClocks[idoRoundId].hasWhitelist, "Whitelist is already disabled.");
        }

        idoRoundClocks[idoRoundId].hasWhitelist = status;
        emit WhitelistStatusChanged(idoRoundId, status);
    }

    /**
        * @notice Sets the maximum allowable contribution with fyTokens as a percentage of the total IDO size, measured in basis points.
        * @dev Updates the maximum basis points for fyToken contributions for a specified IDO. This setting is locked once the IDO starts.
        * @param idoRoundId The identifier for the specific IDO.
        * @param newFyTokenMaxBasisPoints The new maximum basis points (bps) limit for fyToken contributions. One basis point equals 0.01%.
        * Can only be set to a value between 0 and 10,000 basis points (0% to 100%).
        */
    function setFyTokenMaxBasisPoints(uint32 idoRoundId, uint16 newFyTokenMaxBasisPoints) external onlyOwner {
        IDORoundClock storage idoClock = idoRoundClocks[idoRoundId];
        require(newFyTokenMaxBasisPoints <= 10000, "Basis points cannot exceed 10000");
        require(block.timestamp < idoClock.idoStartTime, "Cannot change settings after IDO start");

        IDORoundConfig storage idoConfig = idoRoundConfigs[idoRoundId];
        idoConfig.fyTokenMaxBasisPoints = newFyTokenMaxBasisPoints;

        emit FyTokenMaxBasisPointsChanged(idoRoundId, newFyTokenMaxBasisPoints);
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
            Position storage position = idoRoundConfigs[roundId].accountPositions[participant];
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
            IDORoundConfig storage round = idoRoundConfigs[roundId];

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

    // ======================================    
    // =============== REGISTER ==============
    // ======================================    

    /**
     * @notice Registers the sender in the specified MetaIDO if registration is open.
     * @dev Registers `msg.sender` to `metaIdoId` during the allowed registration period.
     * @param metaIdoId The identifier of the MetaIDO to register for.
     */
    function registerForMetaIDO(uint32 metaIdoId) external {
        MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        require(metaIDO.registrationEndTime != metaIDO.registrationStartTime, "Registration disabled for users");
        // In case we want to disable users from registrating themselves. Effectively a whitelist.

        require(block.timestamp >= metaIDO.registrationStartTime, "Registration has not started yet");
        require(block.timestamp <= metaIDO.registrationEndTime, "Registration has ended");

        require(!metaIDO.isRegistered[msg.sender], "User already registered");

        metaIDO.isRegistered[msg.sender] = true;
        emit UserRegistered(metaIdoId, msg.sender);
    }

    /**
     * @notice Registers multiple users to a MetaIDO regardless of the registration period, only callable by the contract owner.
     * @dev Allows batch registration of users by an admin for `metaIdoId`.
     * @param metaIdoId The identifier of the MetaIDO.
     * @param users An array of user addresses to register.
     */
    function adminAddRegForMetaIDO(uint32 metaIdoId, address[] calldata users) external onlyOwner {
        require(metaIdoId < nextMetaIdoId, "MetaIDO does not exist");
        
        MetaIDO storage metaIDO = metaIDOs[metaIdoId];
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

        MetaIDO storage metaIDO = metaIDOs[metaIdoId];
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
        MetaIDO storage newMetaIDO = metaIDOs[metaIdoId];
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

        MetaIDO storage metaIDO = metaIDOs[metaIdoId];

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
        MetaIDO storage metaIDO = metaIDOs[metaIdoId];
        require(newTime > metaIDO.registrationEndTime, "New registration end time must be after current end time");
        require(newTime <= metaIDO.initialRegistrationEndTime + 2 weeks, "New registration end time exceeds 2 weeks from initial end time");

        emit MetaIDORegEndTimeDelayed(metaIdoId, metaIDO.registrationEndTime, newTime);

        metaIDO.registrationEndTime = newTime;
    }
}


