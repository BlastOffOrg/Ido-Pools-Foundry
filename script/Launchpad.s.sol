// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

// forge clean && source .env && forge script script/Launchpad.s.sol:CreateRound --fork-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast

// Create round
contract CreateRound is Script {
    function run() external {
        // Load the contract address from .env file
        address launchpadContractAddress = vm.envAddress("IDO_POOL_PROXY_CA");
        address buyTokenAddress = vm.envAddress("MOCK_USDB");

        // Start broadcast to sign transactions with private key
        vm.startBroadcast();

        // Instantiate contract
        ILaunchpadContract launchpadContract = ILaunchpadContract(launchpadContractAddress);

        // Get round next ID
        uint32 idoRoundId = launchpadContract.nextIdoRoundId();

        // createIDORound
        uint64 currentTimestamp = uint64(block.timestamp);
        launchpadContract.createIDORound(
            "Yasu round",
            0x8E4227D387A7e084b96646212faBfA6DB5E62ad2,
            0x1733Dab97Db54cAdEaEe716FE1ba3EF358A40491,
            0xF554fE3A9C462b0D72A4e1DEa6801EeA98FcF86d,
            20000000000000000000,
            1000000000000000000000,
            0,
            0,
            currentTimestamp + 20 minutes,
            currentTimestamp + 21 minutes,
            currentTimestamp + 22 minutes
        );

        // setIDORoundSpecs
        launchpadContract.setIDORoundSpecs(
            idoRoundId,
            1,
            5,
            2000000000000000000000,
            1,
            2,
            false,
            false,
            true
        );


        // manageRoundToMetaIDO
        uint32 metaIdoId = launchpadContract.nextMetaIdoId();
        launchpadContract.manageRoundToMetaIDO(metaIdoId - 1, idoRoundId, true);

        // enableIDORound
        // -- Step 1: Mint some buyToken to the launchpad contract address
        IBuyTokenContract buyTokenContract = IBuyTokenContract(buyTokenAddress);
        buyTokenContract.mint(launchpadContractAddress, 1000000000000000000000);

        // -- Step 2: Enable
        launchpadContract.enableIDORound(metaIdoId);

        // End broadcast
        vm.stopBroadcast();
    }
}

// Contracts
// -- Launchpad
interface ILaunchpadContract {
    function nextMetaIdoId() external view returns (uint32);

    function nextIdoRoundId() external view returns (uint32);

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
    ) external;

    function setIDORoundSpecs(
        uint32 idoRoundId,
        uint16 minRank,
        uint16 maxRank,
        uint256 maxAlloc,
        uint256 minAlloc,
        uint16 maxAllocMultiplier,
        bool noMultiplier,
        bool noRank,
        bool standardMaxAllocMult
    ) external;

    function manageRoundToMetaIDO(uint32 metaIdoId, uint32 roundId, bool addRound) external;

    function enableIDORound(uint32 idoRoundId) external;
}

// -- buy token
interface IBuyTokenContract {
    function mint(address recipient, uint256 amount) external;
}


