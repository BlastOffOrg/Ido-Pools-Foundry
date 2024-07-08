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

    struct IDO {
        string idoName;
        address idoToken;
        address buyToken;
        address fyToken;
        uint256 idoPrice;
        uint256 idoSize;
        uint256 idoStartTime;
        uint256 idoEndTime;
        uint256 minimumFundingGoal;
        uint256 fundedUSDValue;
        uint256 claimableTime;
        uint256 initialClaimableTime;
        uint256 initialIdoEndTime;
        uint8 idoTokenDecimals;
        bool isFinalized;
        mapping(address => uint256) totalFunded;
        mapping(address => Position) accountPositions;
    }

    mapping(uint256 => IDO) public idos;
    uint256 public nextIdoId;

    modifier notFinalized(uint256 idoId) {
        if (idos[idoId].isFinalized) revert AlreadyFinalized();
        _;
    }

    modifier finalized(uint256 idoId) {
        if (!idos[idoId].isFinalized) revert NotFinalized();
        _;
    }

    modifier afterStart(uint256 idoId) {
        if(block.timestamp < idos[idoId].idoStartTime) revert NotStarted();
        _;
    }

    modifier claimable(uint256 idoId) {
        if (!idos[idoId].isFinalized) revert NotFinalized();
        if (block.timestamp < idos[idoId].claimableTime) revert NotClaimable();
        _;
    }

    function __IDOPoolAbstract_init(address treasury_) internal onlyInitializing {
        treasury = treasury_;
        __Ownable2Step_init();
    }

    function createIDO(
        string memory idoName,
        address idoToken,
        address buyToken,
        address fyToken,
        uint256 idoPrice,
        uint256 idoSize,
        uint256 idoStartTime,
        uint256 idoEndTime,
        uint256 minimumFundingGoal,
        uint256 claimableTime
    ) external onlyOwner {
        require(idoEndTime > idoStartTime, "End time must be after start time");
        IDO storage ido = idos[nextIdoId];
        ido.idoName = idoName;
        ido.idoToken = idoToken;
        ido.buyToken = buyToken;
        ido.fyToken = fyToken;
        ido.idoPrice = idoPrice;
        ido.idoSize = idoSize;
        ido.idoStartTime = idoStartTime;
        ido.idoEndTime = idoEndTime;
        ido.minimumFundingGoal = minimumFundingGoal;
        ido.claimableTime = claimableTime;
        ido.initialClaimableTime = claimableTime;
        ido.initialIdoEndTime = idoEndTime;
        ido.idoTokenDecimals = ERC20(idoToken).decimals();
        ido.isFinalized = false;
        
        emit IDOCreated(nextIdoId, idoName, idoToken, idoPrice, idoSize, idoStartTime, idoEndTime, minimumFundingGoal, claimableTime);

        nextIdoId++;


    }

    function _getTokenUSDPrice() internal view virtual returns (uint256 price, uint256 decimals);

    /**
     * @notice Finalize the IDO pool for a specific IDO.
     * @dev This function finalizes the given IDO, calculates the total value of USD funded, and determines the IDO size.
     * It cannot be finalized if the IDO has not reached its end time or the minimum funding goal is not met.
     * @param idoId The ID of the IDO to finalize.
     */
    function finalize(uint256 idoId) external onlyOwner notFinalized(idoId) {
        IDO storage ido = idos[idoId];
        ido.idoSize = IERC20(ido.idoToken).balanceOf(address(this));
        (uint256 snapshotTokenPrice, uint256 snapshotPriceDecimals) = _getTokenUSDPrice();
        ido.fundedUSDValue = ((ido.totalFunded[ido.buyToken] + ido.totalFunded[ido.fyToken]) * snapshotTokenPrice) / snapshotPriceDecimals;
        
        if (block.timestamp < ido.idoEndTime) revert IDONotEnded();
        if (ido.fundedUSDValue < ido.minimumFundingGoal) revert FudingGoalNotReached();
        
        ido.isFinalized = true;

        emit Finalized(ido.idoSize, ido.fundedUSDValue);
    }


    /**
     * @notice Calculate the amount of IDO tokens receivable by the staker for a specific IDO.
     * @dev This function calculates the allocated and excessive amounts of IDO tokens for the staker based on their position.
     * @dev might use `IDO memory ido` if it helps save gas.`
     * @param idoId The ID of the IDO.
     * @param pos The position of the staker.
     * @return allocated The amount of IDO tokens allocated to the staker.
     * @return excessive The amount of excess funds to be refunded to the staker.
     */
    function _getPositionValue(uint256 idoId, Position memory pos) internal view returns (uint256 allocated, uint256 excessive) {
        IDO storage ido = idos[idoId];
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
    function _refundPosition(uint256 idoId, Position memory pos, address staker, uint256 excessAmount) internal {
        IDO storage ido = idos[idoId];
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
    function _depositToTreasury(uint256 idoId, Position memory pos) internal {
        IDO storage ido = idos[idoId];
        TokenTransfer._transferToken(ido.fyToken, treasury, pos.fyAmount);
        TokenTransfer._transferToken(ido.buyToken, treasury, pos.amount - pos.fyAmount);
    }
    
    
    /**
     * @notice Participate in a specific IDO.
     * @dev This function allows a recipient to participate in a given IDO by contributing a specified amount of tokens.
     * The token used for participation must be either the buyToken or fyToken of the IDO.
     * @param idoId The ID of the IDO to participate in.
     * @param recipient The address of the recipient participating in the IDO.
     * @param token The address of the token used to participate, must be either the buyToken or fyToken.
     * @param amount The amount of the token to participate with.
    */ 
    function participate(
        uint256 idoId, 
        address recipient, 
        address token, 
        uint256 amount
    ) external payable notFinalized(idoId) afterStart(idoId) {
        IDO storage ido = idos[idoId];
        if (token != ido.buyToken && token != ido.fyToken) {
            revert InvalidParticipateToken(token);
        }

        Position storage position = ido.accountPositions[recipient];
        if (token == ido.fyToken) {
            position.fyAmount += amount;
        }

        position.amount += amount;
        ido.totalFunded[token] += amount;

        // take token from transaction sender to register recipient
        TokenTransfer._depositToken(token, msg.sender, amount);
        emit Participation(recipient, token, amount);
    }


    /**
     * @notice Claim refund and IDO tokens for a specific IDO.
     * @dev This function allows a staker to claim their allocated IDO tokens and any excess funds for a given IDO.
     * @param idoId The ID of the IDO.
     * @param staker The address of the staker claiming the IDO tokens.
     */

    function claim(uint256 idoId, address staker) external claimable(idoId) {
        IDO storage ido = idos[idoId];
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
    function withdrawSpareIDO(uint256 idoId) external notFinalized(idoId) onlyOwner {
        IDO storage ido = idos[idoId];
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
     * later than the current claimable time and does not exceed two weeks from the initial claimable time.
     * @param idoId The ID of the IDO to update.
     * @param _newTime The new claimable time to set.
     */
    function delayClaimableTime(uint256 idoId, uint256 _newTime) external onlyOwner {
        IDO storage ido = idos[idoId];
        require(_newTime > ido.initialClaimableTime, "New claimable time must be after current claimable time");
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
    function delayIdoEndTime(uint256 idoId, uint256 _newTime) external onlyOwner {
        IDO storage ido = idos[idoId];
        require(_newTime > ido.initialIdoEndTime, "New IDO end time must be after initial IDO end time");
        require(_newTime <= ido.initialIdoEndTime + 2 weeks, "New IDO end time exceeds 2 weeks from initial IDO end time");
        emit IdoEndTimeDelayed(ido.idoEndTime, _newTime);


        ido.idoEndTime = _newTime;
    }


    /**
    * @dev Returns the name of the IDO associated with the given idoId.
    * @param idoId The ID of the IDO.
    * @return idoName The name of the IDO.
    */
    function getIdoName(uint256 idoId) public view returns (string memory) {
        require(idoId < nextIdoId, "IDO does not exist");
        return idos[idoId].idoName;
    }


}


