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
    }

    struct IDOClock {
        uint64 idoStartTime;
        uint64 claimableTime;
        uint64 initialClaimableTime;
        uint64 idoEndTime;
        uint64 initialIdoEndTime;
        bool isFinalized;
        bool hasWhitelist; 
        bool hasExceedCap;
    }

    struct IDOConfig {
        address idoToken;
        uint8 idoTokenDecimals;
        uint16 fyTokenMaxBasisPoints;
        address buyToken;
        address fyToken;
        uint256 idoPrice;
        uint256 idoSize;
        uint256 minimumFundingGoal;
        uint256 fundedUSDValue;
        mapping(address => bool) whitelist;
        mapping(address => uint256) totalFunded;
        mapping(address => Position) accountPositions;
    }

    mapping(uint32 => IDOClock) public idoClocks;
    mapping(uint32 => IDOConfig) public idoConfigs;

    uint32 public nextIdoId = 1;

    modifier notFinalized(uint32 idoId) {
        if (idoClocks[idoId].isFinalized) revert AlreadyFinalized();
        _;
    }

    modifier finalized(uint32 idoId) {
        if (!idoClocks[idoId].isFinalized) revert NotFinalized();
        _;
    }

    modifier afterStart(uint32 idoId) {
        if(block.timestamp < idoClocks[idoId].idoStartTime) revert NotStarted();
        _;
    }

    modifier claimable(uint32 idoId) {
        if (!idoClocks[idoId].isFinalized) revert NotFinalized();
        if (block.timestamp < idoClocks[idoId].claimableTime) revert NotClaimable();
        _;
    }

    function __IDOPoolAbstract_init(address treasury_) internal onlyInitializing {
        treasury = treasury_;
        __Ownable2Step_init();
    }

    function createIDO(
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
        uint32 idoId = nextIdoId ++; // postfix increment
        idoClocks[idoId] = IDOClock({
            idoStartTime: idoStartTime,
            claimableTime: claimableTime,
            initialClaimableTime: claimableTime,
            idoEndTime: idoEndTime,
            initialIdoEndTime: idoEndTime,
            isFinalized: false,
            hasWhitelist: false,
            hasExceedCap: false
        });

        //IDOConfig needs to be assigned like this, Nested mapping error.
        IDOConfig storage config = idoConfigs[idoId];
        config.idoToken = idoToken;
        config.idoTokenDecimals = ERC20(idoToken).decimals();
        config.buyToken = buyToken;
        config.fyToken = fyToken;
        config.idoPrice = idoPrice;
        config.idoSize = idoSize;
        config.minimumFundingGoal = minimumFundingGoal;
        config.fyTokenMaxBasisPoints = fyTokenMaxBasisPoints;
        config.fundedUSDValue = 0;
        
        emit IDOCreated(idoId, idoName, idoToken, idoPrice, idoSize, minimumFundingGoal, idoStartTime, idoEndTime, claimableTime);
    }

    function _getTokenUSDPrice() internal view virtual returns (uint256 price, uint256 decimals);

    /**
     * @notice Finalize the IDO pool for a specific IDO.
     * @dev This function finalizes the given IDO, calculates the total value of USD funded, and determines the IDO size.
     * It cannot be finalized if the IDO has not reached its end time or the minimum funding goal is not met.
     * @param idoId The ID of the IDO to finalize.
     */
    function finalize(uint32 idoId) external onlyOwner notFinalized(idoId) {
        IDOClock storage idoClock = idoClocks[idoId];
        IDOConfig storage idoConfig = idoConfigs[idoId];
        idoConfig.idoSize = IERC20(idoConfig.idoToken).balanceOf(address(this));
        (uint256 snapshotTokenPrice, uint256 snapshotPriceDecimals) = _getTokenUSDPrice();
        idoConfig.fundedUSDValue = ((idoConfig.totalFunded[idoConfig.buyToken] + idoConfig.totalFunded[idoConfig.fyToken]) * snapshotTokenPrice) / snapshotPriceDecimals;
        
        if (block.timestamp < idoClock.idoEndTime) revert IDONotEnded();
        if (idoConfig.fundedUSDValue < idoConfig.minimumFundingGoal) revert FudingGoalNotReached();
        
        idoClock.isFinalized = true;

        emit Finalized(idoConfig.idoSize, idoConfig.fundedUSDValue);
    }


    /**
     * @notice Calculate the amount of IDO tokens receivable by the staker for a specific IDO.
     * @dev This function calculates the allocated and excessive amounts of IDO tokens for the staker based on their position.
     * @dev might use `IDO memory ido` if it helps save gas.`
     * @dev TODO fix the precision loss of 1 in the `exessiveTokens`. 
     * @param idoId The ID of the IDO.
     * @param pos The position of the staker.
     * @return allocated The amount of IDO tokens allocated to the staker.
     * @return excessive The amount of excess funds to be refunded to the staker.
     */
    function _getPositionValue(uint32 idoId, Position memory pos) internal view returns (uint256 allocated, uint256 excessive) {
        IDOConfig storage ido = idoConfigs[idoId];
        uint256 posInUSD = (pos.amount * ido.fundedUSDValue) / ido.idoPrice; // position value in USD

        uint256 idoExp = 10 ** ido.idoTokenDecimals;
        // amount of IDO received if exceeded funding goal
        uint256 exceedAlloc = (ido.idoSize * posInUSD) / ido.fundedUSDValue;
        // amount of IDO token received if not exceeded goal
        uint256 buyAlloc = (posInUSD * idoExp) / ido.idoPrice;

        if ((ido.idoSize * ido.idoPrice / idoExp) >= ido.fundedUSDValue) {
            return (buyAlloc, 0);
        } else {
            uint256 excessiveInUSD = posInUSD - ((exceedAlloc * idoExp) / ido.idoPrice);
            uint256 excessiveTokens = (excessiveInUSD * ido.fundedUSDValue) / ido.idoPrice;
            return (exceedAlloc, excessiveTokens);
        }
    }

        /**
     * @notice Refund staker after claim and transfer remaining funds to the treasury for a specific IDO.
     * @dev This function refunds the staker any excess funds and transfers the remaining funds to the treasury.
     * @dev might use `IDO memory ido` if it helps save gas.`
     * @param idoId The ID of the IDO.
     * @param pos The position of the staker.
     * @param staker The address of the staker to refund.
     * @param excessAmount The amount to refund to the staker.
     */
    function _refundPosition(uint32 idoId, Position memory pos, address staker, uint256 excessAmount) internal {
        IDOConfig storage ido = idoConfigs[idoId];
        if (excessAmount <= pos.fyAmount) {
            TokenTransfer._transferToken(ido.fyToken, staker, excessAmount);
            TokenTransfer._transferToken(ido.fyToken, treasury, pos.fyAmount - excessAmount);
            TokenTransfer._transferToken(ido.buyToken, treasury, pos.amount - pos.fyAmount);
        } else {
            TokenTransfer._transferToken(ido.fyToken, staker, pos.fyAmount);
            TokenTransfer._transferToken(ido.buyToken, staker, excessAmount - pos.fyAmount);
            TokenTransfer._transferToken(ido.buyToken, treasury, pos.amount - excessAmount);
        }
    }

    /**
     * @notice Transfer the staker's funds to the treasury for a specific IDO.
     * @dev This function transfers the staker's funds to the treasury.
     * @param idoId The ID of the IDO.
     * @param pos The position of the staker.
     */
    function _depositToTreasury(uint32 idoId, Position memory pos) internal {
        IDOConfig storage ido = idoConfigs[idoId];
        TokenTransfer._transferToken(ido.fyToken, treasury, pos.fyAmount);
        TokenTransfer._transferToken(ido.buyToken, treasury, pos.amount - pos.fyAmount);
    }
    
    
    /**
     * @notice Participate in a specific IDO.
     * @dev This function allows a recipient to participate in a given IDO by contributing a specified amount of tokens.
     * Checks have been delegated to the `_participationCheck` function
     * The token used for participation must be either the buyToken or fyToken of the IDO.
     * @param idoId The ID of the IDO to participate in.
     * @param recipient The address of the recipient participating in the IDO.
     * @param token The address of the token used to participate, must be either the buyToken or fyToken.
     * @param amount The amount of the token to participate with.
    */ 
    function participate(
        uint32 idoId, 
        address recipient, 
        address token, 
        uint256 amount
    ) external payable notFinalized(idoId) afterStart(idoId) {
        IDOConfig storage idoConfig = idoConfigs[idoId];

        _participationCheck(idoId, recipient, token, amount); // Perform all participation checks

        Position storage position = idoConfig.accountPositions[recipient];
        uint256 newTotalFunded = idoConfig.totalFunded[token] + amount;

        if (token == idoConfig.fyToken) {
            position.fyAmount += amount;
        }

        position.amount += amount;
        idoConfig.totalFunded[token] = newTotalFunded;

        // take token from transaction sender to register recipient
        TokenTransfer._depositToken(token, msg.sender, amount);
        emit Participation(recipient, token, amount);
    }

    /**
     * @dev Checks all conditions for participation in an IDO, including whitelist validation if required. Reverts if any conditions are not met.
     * @param idoId The ID of the IDO.
     * @param recipient The address of the participant.
     * @param token The token used for participation.
     * @param amount The amount of the token.
     syntax on
    */


    function _participationCheck(uint32 idoId, address recipient, address token, uint256 amount) internal view {
        IDOConfig storage idoConfig = idoConfigs[idoId];
        IDOClock storage idoClock = idoClocks[idoId];

        // Cache storage variables used multiple times to memory
        address buyToken = idoConfig.buyToken;
        address fyToken = idoConfig.fyToken;

        // Check if the token is a valid participation token
        if (token != buyToken && token != fyToken) {
            revert InvalidParticipateToken(token);
        }

        // Check whitelisting if enabled for this IDO
        if (idoClock.hasWhitelist && !idoConfig.whitelist[recipient]) {
            revert("Recipient not whitelisted");
        }

        // Perform calculations after cheaper checks have passed
        uint256 globalTotalFunded = idoConfig.totalFunded[buyToken] + idoConfig.totalFunded[fyToken] + amount;

        // Check fyToken contribution limits
        if (token == fyToken) {
            uint256 maxFyTokenFunding = (idoConfig.idoSize * idoConfig.fyTokenMaxBasisPoints) / 10000;
            require(globalTotalFunded <= maxFyTokenFunding, "fyToken contribution exceeds limit");
        }

        // Check overall contribution cap unless the cap can be exceeded
        if (!idoClock.hasExceedCap) {
            require(globalTotalFunded <= idoConfig.idoSize, "Contribution exceeds IDO cap");
        }
    }


    /**
     * @notice Claim refund and IDO tokens for a specific IDO.
     * @dev This function allows a staker to claim their allocated IDO tokens and any excess funds for a given IDO.
     * @param idoId The ID of the IDO.
     * @param staker The address of the staker claiming the IDO tokens.
     */

    function claim(uint32 idoId, address staker) external claimable(idoId) {
        IDOConfig storage ido = idoConfigs[idoId];
        Position memory pos = ido.accountPositions[staker];
        if (pos.amount == 0) revert NoStaking();

        (uint256 alloc, uint256 excessive) = _getPositionValue(idoId, pos);

        delete ido.accountPositions[staker];

        if (excessive > 0) _refundPosition(idoId, pos, staker, excessive);
        else _depositToTreasury(idoId, pos);

        TokenTransfer._transferToken(ido.idoToken, staker, alloc);

        emit Claim(staker, alloc, excessive);
    }

    /**
     * @notice Withdraw remaining IDO tokens if the funding goal is not reached.
     * @dev This function allows the owner to withdraw unsold IDO tokens if the funding goal is not reached.
     * @param idoId The ID of the IDO.
     */
    function withdrawSpareIDO(uint32 idoId) external notFinalized(idoId) onlyOwner {
        IDOConfig storage ido = idoConfigs[idoId];
        uint8 decimals = ido.idoTokenDecimals;
        uint256 totalIDOGoal = (ido.idoSize * ido.idoPrice) / (10 ** decimals);
        if (totalIDOGoal <= ido.fundedUSDValue) revert FudingGoalNotReached();

        uint256 totalBought = ido.fundedUSDValue / ido.idoPrice * (10 ** decimals);
        uint256 idoBal = IERC20(ido.idoToken).balanceOf(address(this));
        uint256 spare = idoBal - totalBought;
        TokenTransfer._transferToken(ido.idoToken, msg.sender, spare);
    }

    /**
     * @notice Delays the claimable time for a specific IDO.
     * @dev This function updates the claimable time for the given IDO to a new time, provided the new time is 
     * later than the current claimable time, later than the idoEndTime 
     * and does not exceed two weeks from the initial claimable time.
     * @param idoId The ID of the IDO to update.
     * @param _newTime The new claimable time to set.
     */
    function delayClaimableTime(uint32 idoId, uint64 _newTime) external onlyOwner {
        IDOClock storage ido = idoClocks[idoId];
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
     * @param idoId The ID of the IDO to update.
     * @param _newTime The new end time to set.
     */
    function delayIdoEndTime(uint32 idoId, uint64 _newTime) external onlyOwner {
        IDOClock storage ido = idoClocks[idoId];
        require(_newTime > ido.initialIdoEndTime, "New IDO end time must be after initial IDO end time");
        require(_newTime <= ido.initialIdoEndTime + 2 weeks, "New IDO end time exceeds 2 weeks from initial IDO end time");
        emit IdoEndTimeDelayed(ido.idoEndTime, _newTime);


        ido.idoEndTime = _newTime;
    }

    /**
     * @notice Modifies the whitelist status for a list of participants for a specific IDO.
     * @dev Adds or removes addresses from the whitelist mapping in the IDOConfig for the specified IDO, based on the flag.
     * @param idoId The ID of the IDO.
     * @param participants The array of addresses of the participants to modify.
     * @param addToWhitelist True to add to the whitelist, false to remove from the whitelist.
     */
    function modifyWhitelist(uint32 idoId, address[] calldata participants, bool addToWhitelist) external onlyOwner {
        require(idoClocks[idoId].hasWhitelist, "Whitelist not enabled for this IDO.");
        require(participants.length > 0, "Participant list cannot be empty.");

        for (uint i = 0; i < participants.length; i++) {
            idoConfigs[idoId].whitelist[participants[i]] = addToWhitelist;
        }
    }

    /**
     * @notice Sets the whitelist status for a specific IDO.
     * @dev Enables or disables the whitelist for an IDO. Whitelisting cannot be enabled once the IDO has started.
     *      Disabling can occur at any time unless the IDO is finalized or the whitelist is already disabled.
     *      Can only be called by the owner.
     * @param idoId The ID of the IDO.
     * @param status True to enable the whitelist, false to disable it.
     */
    function setWhitelistStatus(uint32 idoId, bool status) external onlyOwner {
        if (status) {
            require(block.timestamp < idoClocks[idoId].idoStartTime, "Cannot enable whitelist after IDO start.");
        } else {
            require(!idoClocks[idoId].isFinalized, "IDO is already finalized.");
            require(idoClocks[idoId].hasWhitelist, "Whitelist is already disabled.");
        }
        
        idoClocks[idoId].hasWhitelist = status;
        emit WhitelistStatusChanged(idoId, status);
    }

    /**
     * @notice Sets the status of whether an IDO can exceed its predefined cap.
     * @dev Allows toggling the capability to accept contributions beyond the set IDO cap.
     *      This setting cannot be changed once the IDO has started to ensure fairness.
     * @param idoId The identifier for the specific IDO.
     * @param status True to allow contributions to exceed the cap, false to enforce the cap strictly.
     */
    function setCapExceedStatus(uint32 idoId, bool status) external onlyOwner {
        require(block.timestamp < idoClocks[idoId].idoStartTime, "Cannot change cap status after IDO start.");
        idoClocks[idoId].hasExceedCap = status;
        emit CapExceedStatusChanged(idoId, status);
    }

    /**
     * @notice Sets the maximum allowable contribution with fyTokens as a percentage of the total IDO size, measured in basis points.
     * @dev Updates the maximum basis points for fyToken contributions for a specified IDO. This setting is locked once the IDO starts.
     * @param idoId The identifier for the specific IDO.
     * @param newFyTokenMaxBasisPoints The new maximum basis points (bps) limit for fyToken contributions. One basis point equals 0.01%.
     * Can only be set to a value between 0 and 10,000 basis points (0% to 100%).
     */
    function setFyTokenMaxBasisPoints(uint32 idoId, uint16 newFyTokenMaxBasisPoints) external onlyOwner {
    IDOClock storage idoClock = idoClocks[idoId];
    require(newFyTokenMaxBasisPoints <= 10000, "Basis points cannot exceed 10000");
    require(block.timestamp < idoClock.idoStartTime, "Cannot change settings after IDO start");

    IDOConfig storage idoConfig = idoConfigs[idoId];
    idoConfig.fyTokenMaxBasisPoints = newFyTokenMaxBasisPoints;

    emit FyTokenMaxBasisPointsChanged(idoId, newFyTokenMaxBasisPoints);
    }

}


