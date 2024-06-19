// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IDOPoolAbstract.sol";
import "./oracle/ETHPriceOracle.sol";

contract ETHIDOPool is Initializable, IDOPoolAbstract, ETHPriceOracle {
  function init(
    address fyETH_,
    address idoToken_,
    uint256 idoDecimals_,
    address treasury_,
    bool mock_,
    uint256 idoStartTime_,
    uint256 idoEndTime_,
    uint256 minimumFundingGoal_,
    uint256 idoPrice_
  ) external initializer {
    __IDOPoolAbstract_init(
      address(0),
      fyETH_,
      idoToken_,
      idoDecimals_,
      treasury_,
      idoStartTime_,
      idoEndTime_,
      minimumFundingGoal_,
      idoPrice_
    );
    __ETHPriceOracle_init(mock_);
  }

  function _getTokenUSDPrice()
    internal
    view
    virtual
    override
    returns (uint256, uint256)
  {
    return (getETHPrice(), 1e8);
  }
}
