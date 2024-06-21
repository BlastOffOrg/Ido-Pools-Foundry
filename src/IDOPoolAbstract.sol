// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "./interface/IIDOPool.sol";
import "./lib/TokenTransfer.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

abstract contract IDOPoolAbstract is IIDOPool, Ownable2StepUpgradeable {
    address public buyToken;
    address public fyToken;
    address public treasury;

    address public idoToken;
    bool public isFinalized;
    uint256 public claimableTime;

    uint256 public idoPrice; // expected price of ido decimal is ido token decimal
    uint256 public idoSize; // total amount of ido token
    uint256 public snapshotTokenPrice;
    uint256 public snapshotPriceDecimals;
    uint256 public fundedUSDValue;
    uint256 public idoDecimals;
    mapping(address => uint256) public totalFunded;
    mapping(address => Position) public accountPosition;

    uint256 public minimumFundingGoal;
    uint256 public idoStartTime;
    uint256 public idoEndTime;

    uint256 public initialClaimableTime;
    uint256 public initialIdoEndTime;

    modifier notFinalized() {
        if (isFinalized) revert AlreadyFinalized();
        _;
    }

    modifier finalized() {
        if (!isFinalized) revert NotFinalized();
        _;
    }

    modifier afterStart() {
        if (block.timestamp < idoStartTime) revert NotStarted();
        _;
    }

    modifier claimable() {
        if (!isFinalized) revert NotFinalized();
        if (block.timestamp < claimableTime) revert NotClaimable();
        _;
    }

    function __IDOPoolAbstract_init(
        address buyToken_,
        address fyToken_,
        address idoToken_,
        address treasury_,
        uint256 idoStartTime_,
        uint256 idoEndTime_,
        uint256 minimumFundingGoal_,
        uint256 price_,
        uint256 claimableTime_
    ) internal onlyInitializing {
        __IDOPoolAbstract_init_unchained(
            buyToken_,
            fyToken_,
            idoToken_,
            treasury_,
            idoStartTime_,
            idoEndTime_,
            minimumFundingGoal_,
            price_,
            claimableTime_
        );
        __Ownable2Step_init();
    }

    function __IDOPoolAbstract_init_unchained(
        address buyToken_,
        address fyToken_,
        address idoToken_,
        // uint256 idoDecimals_,
        address treasury_,
        uint256 idoStartTime_,
        uint256 idoEndTime_,
        uint256 minimumFundingGoal_,
        uint256 price_,
        uint256 claimableTime_
    ) internal onlyInitializing {
        buyToken = buyToken_;
        fyToken = fyToken_;
        idoToken = idoToken_;
        idoDecimals = ERC20(idoToken_).decimals();
        treasury = treasury_;
        idoStartTime = idoStartTime_;
        idoEndTime = idoEndTime_;
        initialIdoEndTime = idoEndTime_;
        minimumFundingGoal = minimumFundingGoal_;
        idoPrice = price_;
        claimableTime = claimableTime_;
        initialClaimableTime = claimableTime_;
    }

    function setIDOToken(address _token) external onlyOwner {
        if (isFinalized) revert("InvalidToken");
        idoToken = _token;
        idoDecimals = ERC20(_token).decimals();
    }

    function _getTokenUSDPrice() internal view virtual returns (uint256 price, uint256 decimals);

    /**
     * @dev finalize the IDO pool
     * cannot finalize if IDO has not reached end time or minimum funding goal is not reached.
     *
     * Finalize will calulate total value of USD funded for IDO and determine IDO size
     */
    function finalize() external onlyOwner notFinalized {
        // removed idoSize here and hardcoded at initialization
        idoSize = IERC20(idoToken).balanceOf(address(this));
        (snapshotTokenPrice, snapshotPriceDecimals) = _getTokenUSDPrice();
        fundedUSDValue = ((totalFunded[buyToken] + totalFunded[fyToken]) * snapshotTokenPrice) / snapshotPriceDecimals;
        if (block.timestamp < idoEndTime) revert IDONotEnded();
        else if (fundedUSDValue < minimumFundingGoal) revert FudingGoalNotReached();
        isFinalized = true;

        emit Finalized(idoSize, fundedUSDValue);
    }

    /**
     * @dev Calculate amount of IDO token receivable by staker
     * @param pos position of staker
     * and amount of stake token to return after finalization
     * @return allocated
     * @return excessive
     */
    function _getPositionValue(Position memory pos) internal view returns (uint256 allocated, uint256 excessive) {
        uint256 posInUSD = (pos.amount * snapshotTokenPrice) / snapshotPriceDecimals; // position value in USD

        uint256 idoExp = 10 ** idoDecimals;
        // amount of ido received if exceeded funding goal
        uint256 exceedAlloc = (idoSize * posInUSD) / fundedUSDValue;
        // amount of ido token received if not exceeded goal
        uint256 buyAlloc = (posInUSD * idoExp) / idoPrice;

        if ((idoSize * idoPrice / idoExp) >= fundedUSDValue) {
            return (buyAlloc, 0);
        } else {  
            // Ensure that the division rounds down
            //uint256 exceedAllocInUSD = (exceedAlloc * idoExp);
            // Calculate the truncated value to handle rounding
            //uint256 truncatedValue = exceedAllocInUSD / idoPrice;
            //uint256 excessiveInUSD = posInUSD > truncatedValue ? posInUSD - truncatedValue : 0;

            uint256 excessiveInUSD = posInUSD - ((exceedAlloc * idoExp) / idoPrice); // Incorrect
            uint256 excessiveTokens = (excessiveInUSD * snapshotPriceDecimals) / snapshotTokenPrice;
            return (exceedAlloc, excessiveTokens);
        }
    }

    /**
     * @dev Refund staker after claim and transfer fund to treasury
     *
     * @param pos position of staker
     * @param staker staker to refund
     * @param excessAmount amount to refund
     */
    function _refundPostition(Position memory pos, address staker, uint256 excessAmount) internal {
        if (excessAmount <= pos.fyAmount) {
            TokenTransfer._transferToken(fyToken, staker, excessAmount);
            TokenTransfer._transferToken(fyToken, treasury, pos.fyAmount - excessAmount);
            TokenTransfer._transferToken(buyToken, treasury, pos.amount - pos.fyAmount);
        } else {
            TokenTransfer._transferToken(fyToken, staker, pos.fyAmount);
            TokenTransfer._transferToken(buyToken, staker, excessAmount - pos.fyAmount);
            TokenTransfer._transferToken(buyToken, treasury, pos.amount - excessAmount);
        }
    }

    function _depositToTreasury(Position memory pos) internal {
        TokenTransfer._transferToken(fyToken, treasury, pos.fyAmount);
        TokenTransfer._transferToken(buyToken, treasury, pos.amount - pos.fyAmount);
    }

    /**
     * @dev Participate in IDO
     *
     * @param receipient address to participate in IDO
     * @param token address of token used to particpate, must be either buyToken or fyToken
     * @param amount amount of token to participate
     */
    function participate(address receipient, address token, uint256 amount) external payable notFinalized afterStart {
        if (token != buyToken && token != fyToken) {
            revert InvalidParticipateToken(token);
        }
        Position storage position = accountPosition[receipient];
        if (token == fyToken) {
            position.fyAmount += amount;
        }

        position.amount += amount;
        totalFunded[token] += amount;

        // take token from transaction sender to register receipient
        TokenTransfer._depositToken(token, msg.sender, amount);
        emit Participation(receipient, token, amount);
    }

    /**
     * @dev Claim refund and IDO token
     *
     * @param staker address of staker to claim IDO token1
     */
    function claim(address staker) external claimable {
        Position memory pos = accountPosition[staker];
        if (pos.amount == 0) revert NoStaking();

        (uint256 alloc, uint256 excessive) = _getPositionValue(pos);

        delete accountPosition[staker];

        if (excessive > 0) _refundPostition(pos, staker, excessive);
        else _depositToTreasury(pos);

        TokenTransfer._transferToken(idoToken, staker, alloc);

        emit Claim(staker, alloc, excessive);
    }

    /**
     * @dev Withdraw remaining IDO token if funding goal is not reached
     */
    function withdrawSpareIDO() external notFinalized onlyOwner {
        uint256 totalIDOGoal = (idoSize * idoPrice) / (10 ** idoDecimals);
        if (totalIDOGoal <= fundedUSDValue) revert();

        uint256 totalBought = fundedUSDValue / idoPrice * (10 ** idoDecimals);
        uint256 idoBal = IERC20(idoToken).balanceOf(address(this));
        uint256 spare = idoBal - totalBought;
        TokenTransfer._transferToken(idoToken, msg.sender, spare);
    }

    function delayClaimableTime(uint256 _newTime) external onlyOwner {
        require(_newTime > claimableTime, "New claimable time must be after current claimable time");
        require(
            _newTime <= initialClaimableTime + 2 weeks, "New claimable time exceeds 2 weeks from initial claimable time"
        );
        emit ClaimableTimeDelayed(claimableTime, _newTime);

        claimableTime = _newTime;
    }

    function delayIdoEndTime(uint256 _newTime) external onlyOwner {
        require(_newTime > idoEndTime, "New IDO end time must be after current IDO end time");
        require(_newTime <= initialIdoEndTime + 2 weeks, "New IDO end time exceeds 2 weeks from initial IDO end time");
        emit IdoEndTimeDelayed(idoEndTime, _newTime);

        idoEndTime = _newTime;
    }
}
