// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/mock/MockERC20.sol";
import "../src/StandardIDOPool.sol";
import "../src/core/IDOStructs.sol";

// Create round
contract CreateRound is Script {
    /**
        * @param metaIdoId The identifier of the meta IDO
    **/
    function run(uint32 metaIdoId) external {
        // Load contract addresses from .env file
        address payable launchpadContractAddress = payable(vm.envAddress("IDO_POOL_PROXY_CA"));
        address buyTokenAddress = vm.envAddress("MOCK_USDB");
        address idoTokenAddress = vm.envAddress("MOCK_IDO_TOKEN2");
        address fyUSDBAddress = vm.envAddress("MOCK_FYUSDB");

        // Start broadcast to sign transactions with private key
        vm.startBroadcast();

        // Instantiate launchpad contract
        StandardIDOPool launchpadContract = StandardIDOPool(launchpadContractAddress);

        // Get round next ID & last metaIdo ID
        uint32 nextIdoRoundId = launchpadContract.nextIdoRoundId();

        // createIDORound
        // Get last meta IDO timestamp
        (uint64 registrationStartTime, ,) = launchpadContract.metaIDOs(metaIdoId);
        launchpadContract.createIDORound(
            "Yasu round",
            idoTokenAddress,
            buyTokenAddress,
            fyUSDBAddress,
            1000000000000000000,
            1000000000000000000000,
            0,
            0,
            registrationStartTime + 20 minutes,
            registrationStartTime + 21 minutes,
            registrationStartTime + 22 minutes
        );

        // setIDORoundSpecs
        launchpadContract.setIDORoundSpecs(
            nextIdoRoundId,
            1,
            5,
            10000000000000000000,
            1,
            2,
            false,
            false,
            true
        );

        // manageRoundToMetaIDO
        launchpadContract.manageRoundToMetaIDO(metaIdoId, nextIdoRoundId, true);

        // enableIDORound
        // -- Step 1: Mint some buyToken & idotoken to the launchpad contract address
        MockERC20 buyTokenContract = MockERC20(buyTokenAddress);
        MockERC20 idoTokenContract = MockERC20(idoTokenAddress);
        buyTokenContract.mint(launchpadContractAddress, 1000000000000000000000);
        idoTokenContract.mint(idoTokenAddress, 1000000000000000000000);

        // -- Step 2: Enable
        launchpadContract.enableIDORound(nextIdoRoundId);

        // End broadcast
        vm.stopBroadcast();
    }
}



