// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "./interface/IIDOPool.sol";
import "./interface/IERC20Mintable.sol";
import "./lib/TokenTransfer.sol";
import "hardhat/console.sol";

abstract contract IDOPoolAbstract is IIDOPool, Ownable2StepUpgradeable {
  address public buyToken;
  address public fyToken;
  address public treasury;

  address public idoToken;
  bool public isFinalized;
  uint256 public claimableTime;
  bool public isClaimable;

  uint256 public idoPrice; // expected price of ido decimal is ido token decimal
  uint256 public idoSize; // total amount of ido token
  uint256 public snapshotTokenPrice;
  uint256 public snapshotPriceDecimals;
  uint256 private fundedUSDValue;
  uint256 private idoDecimals;
  mapping(address => uint256) private totalFunded;
  mapping(address => Position) public accountPosition;

  uint256 public idoStartTime;
  uint256 public idoEndTime;
  uint256 public minimumFundingGoal;

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
  modifier notStart() {
    if (block.timestamp >= idoStartTime) revert AlreadyStarted();
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
    uint256 idoDecimals_,
    address treasury_,
    uint256 idoStartTime_,
    uint256 idoEndTime_,
    uint256 minimumFundingGoal_,
    uint256 price_
  ) internal onlyInitializing {
    __IDOPoolAbstract_init_unchained(
      buyToken_,
      fyToken_,
      idoToken_,
      idoDecimals_,
      treasury_,
      idoStartTime_,
      idoEndTime_,
      minimumFundingGoal_,
      price_
    );
    __Ownable_init();
  }

  function __IDOPoolAbstract_init_unchained(
    address buyToken_,
    address fyToken_,
    address idoToken_,
    uint256 idoDecimals_,
    address treasury_,
    uint256 idoStartTime_,
    uint256 idoEndTime_,
    uint256 minimumFundingGoal_,
    uint256 price_
  ) internal onlyInitializing {
    buyToken = buyToken_;
    fyToken = fyToken_;
    idoToken = idoToken_;
    idoDecimals = idoDecimals_;
    treasury = treasury_;
    idoStartTime = idoStartTime_;
    idoEndTime = idoEndTime_;
    minimumFundingGoal = minimumFundingGoal_;
    idoPrice = price_;
  }

  function setIDOToken(
    address _token,
    uint256 _idoDecimals
  ) external onlyOwner {
    if (isFinalized) revert("InvalidToken");
    idoToken = _token;
    idoDecimals = _idoDecimals;
  }

  function _getTokenUSDPrice()
    internal
    view
    virtual
    returns (uint256 price, uint256 decimals);

  /**
   * @dev finalize the IDO pool
   * cannot finalize if IDO has not reached end time or minimum funding goal is not reached.
   *
   * Finalize will calulate total value of USD funded for IDO and determine IDO size
   */
  function finalize() external onlyOwner notFinalized {
    if (block.timestamp < idoEndTime) revert IDONotEnded();
    else if (idoSize < minimumFundingGoal) revert FudingGoalNotReached();
    (snapshotTokenPrice, snapshotPriceDecimals) = _getTokenUSDPrice();
    fundedUSDValue =
      ((totalFunded[buyToken] + totalFunded[fyToken]) * snapshotTokenPrice) /
      snapshotPriceDecimals;
    idoSize = IERC20(idoToken).balanceOf(address(this));
    isFinalized = true;
  }

  /**
   * @dev Calculate amount of IDO token receivable by staker
   * @param pos position of staker
   * and amount of stake token to return after finalization
   * @return allocated
   * @return excessive
   */
  function _getPostionValue(
    Position memory pos
  ) internal view returns (uint256 allocated, uint256 excessive) {
    uint256 posInUSD = (pos.amount * snapshotTokenPrice) /
      snapshotPriceDecimals; // position value in USD

    uint256 idoExp = (10 ** idoDecimals);
    // amount of ido received if exceeded funding goal
    uint256 exceedAlloc = (idoSize * posInUSD) / fundedUSDValue;
    // amount of ido token received if not exceeded goal
    uint256 buyAlloc = (posInUSD * idoExp) / idoPrice;
    if (((idoSize * idoPrice) / idoExp) >= fundedUSDValue) {
      return (buyAlloc, 0);
    } else {
      uint256 excessiveInUSD = posInUSD - ((exceedAlloc * idoExp) / idoPrice);
      return (
        exceedAlloc,
        (excessiveInUSD * snapshotPriceDecimals) / snapshotTokenPrice
      );
    }
  }

  /**
   * @dev Refund staker after claim and transfer fund to treasury
   *
   * @param pos position of staker
   * @param staker staker to refund
   * @param excessAmount amount to refund
   */
  function _refundPostition(
    Position memory pos,
    address staker,
    uint256 excessAmount
  ) internal {
    if (excessAmount <= pos.fyAmount) {
      TokenTransfer._transferToken(fyToken, staker, excessAmount);
      TokenTransfer._transferToken(
        fyToken,
        treasury,
        pos.fyAmount - excessAmount
      );
      TokenTransfer._transferToken(
        buyToken,
        treasury,
        pos.amount - pos.fyAmount
      );
    } else {
      TokenTransfer._transferToken(fyToken, staker, pos.fyAmount);
      TokenTransfer._transferToken(
        buyToken,
        staker,
        excessAmount - pos.fyAmount
      );
      TokenTransfer._transferToken(
        buyToken,
        treasury,
        pos.amount - excessAmount
      );
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
  function participate(
    address receipient,
    address token,
    uint256 amount
  ) external payable notFinalized afterStart {
    if (token != buyToken && token != fyToken)
      revert InvalidParticipateToken(token);
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

    (uint256 alloc, uint256 excessive) = _getPostionValue(pos);

    delete accountPosition[staker];

    if (excessive > 0) _refundPostition(pos, staker, excessive);
    else _depositToTreasury(pos);

    TokenTransfer._transferToken(idoToken, staker, alloc);

    emit Claim(staker, alloc, excessive);
  }

  /**
   * @dev Withdraw remaining IDO token if funding goal is not reached
   */
  function withdrawSpareIDO() external finalized onlyOwner {
    uint256 totalIDOGoal = (idoSize * idoPrice) / (10 ** idoDecimals);
    if (totalIDOGoal <= fundedUSDValue) revert();

    uint256 totalBought = fundedUSDValue / idoPrice * (10 ** idoDecimals);
    uint256 idoBal = IERC20Mintable(idoToken).balanceOf(address(this));
    uint256 spare = idoBal - totalBought;
    TokenTransfer._transferToken(idoToken, msg.sender, spare);
  }
}
