// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./core/IDOPoolAbstract.sol";

contract StandardIDOPool is Initializable, IDOPoolAbstract {
    function init(
        address treasury_,
        address _multiplierContract
    ) external initializer {
        __IDOPoolAbstract_init(
            treasury_,
            _multiplierContract
        );
    }
}
