// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./IDOPoolAbstract.sol";

contract USDIDOPool is Initializable, IDOPoolAbstract {
    function init(
        address treasury_
    ) external initializer {
        __IDOPoolAbstract_init(
            treasury_
        );
    }

    function _getTokenUSDPrice() internal view virtual override returns (uint256, uint256) {
        return (1, 1);
    }
}
