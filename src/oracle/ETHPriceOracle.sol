// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@redstone-finance/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";
import "@redstone-finance/evm-connector/contracts/mocks/AuthorisedMockSignersBase.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract ETHPriceOracle is
  PrimaryProdDataServiceConsumerBase,
  AuthorisedMockSignersBase,
  Initializable
{
  bool private mock = false;

  function __ETHPriceOracle_init(bool mock_) internal onlyInitializing {
    mock = mock_;
  }

  /**
   *
   * Get ETH pricing from redstone oracles on blast network
   * result is in 8 decimals
   *
   */
  function getETHPrice() public view returns (uint256) {
    return getOracleNumericValueFromTxMsg(bytes32("ETH"));
  }

  function getAuthorisedSignerIndex(
    address _signer
  ) public view override returns (uint8) {
    if (mock) return getAllMockAuthorised(_signer);
    else return super.getAuthorisedSignerIndex(_signer);
  }
}
