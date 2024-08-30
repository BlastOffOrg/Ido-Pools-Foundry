// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";

contract StandardIDOPoolBasicTest is StandardIDOPoolBaseTest {

    // BASIC CALL, not needed apparently
    //function setUp() public override {
    //  super.setUp();
    //}

    // OVERRIDE TEMPLATE

    //function setUp() public override {
    //    super.setUp(); // Call the base contract's setup

    // Replace the buyToken with a different MockERC20 instance
    //    buyToken = new MockERC20("New Buy Token", "NBUY");

    // If the new `buyToken` impacts other parts of the setup, modify them here
    // For example, if you need to reinitialize something with the new buyToken, do it here
    //}
    function createTestIDORound() internal returns (uint32) {
        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            1 ether, // idoPrice
            1000 ether, // idoSize
            500 ether, // minimumFundingGoal
            5000, // fyTokenMaxBasisPoints (50%)
            uint64(block.timestamp + 1 days), // idoStartTime
            uint64(block.timestamp + 8 days), // idoEndTime
            uint64(block.timestamp + 15 days) // claimableTime
        );
        return idoPool.nextIdoRoundId() - 1;
    }

    function test_1_1_InitialSetup() view public {
        assertEq(address(idoPool.multiplierContract()), address(multiplierContract));
        assertEq(idoPool.treasury(), treasury);
        assertEq(idoPool.owner(), admin);
    }

    function test_1_2_CreateIDORound() public {
        vm.prank(admin);

        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            1 ether, // idoPrice
            1000 ether, // idoSize
            500 ether, // minimumFundingGoal
            5000, // fyTokenMaxBasisPoints (50%)
            uint64(block.timestamp + 1 days), // idoStartTime
            uint64(block.timestamp + 8 days), // idoEndTime
            uint64(block.timestamp + 15 days) // claimableTime
        );
        vm.stopPrank();

        uint32 idoRoundId = idoPool.nextIdoRoundId() - 1;
        (address configIdoToken, , , address configBuyToken, address configFyToken, uint256 configIdoPrice, uint256 configIdoSize, , , uint256 configMinimumFundingGoal, ) = idoPool.idoRoundConfigs(idoRoundId);

        assertEq(configIdoToken, address(idoToken));
        assertEq(configBuyToken, address(buyToken));
        assertEq(configFyToken, address(fyToken));
        assertEq(configIdoPrice, 1 ether);
        assertEq(configIdoSize, 1000 ether);
        assertEq(configMinimumFundingGoal, 500 ether);
    }

    // Add more test functions as needed
    function test_1_3_EnableIDORound() public {
        // First create an IDO round
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        // Set IDO round specs
        idoPool.setIDORoundSpecs(
            idoRoundId,
            1, // minRank
            10, // maxRank
            100 ether, // maxAlloc
            1 ether, // minAlloc
            10000, // maxAllocMultiplier (100%)
            false, // noMultiplier
            false, // noRank
            true // standardMaxAllocMult
        );

        // Transfer IDO tokens to the pool
        idoToken.mint(address(idoPool), 1000 ether);

        // Enable the IDO round
        idoPool.enableIDORound(idoRoundId);

        // Check if the round is enabled
        (,,,,,,,, bool isEnabled,) = idoPool.idoRoundClocks(idoRoundId);
        assertTrue(isEnabled);

        vm.stopPrank();
    }
    function test_1_4_DelayIdoEndTime() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        uint64 newEndTime = uint64(block.timestamp + 10 days);
        idoPool.delayIdoEndTime(idoRoundId, newEndTime);

        (,,,uint64 idoEndTime,,,,,,) = idoPool.idoRoundClocks(idoRoundId);
        assertEq(idoEndTime, newEndTime);

        vm.stopPrank();
    }
    function test_1_5_DelayClaimableTime() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        uint64 newClaimableTime = uint64(block.timestamp + 20 days);
        idoPool.delayClaimableTime(idoRoundId, newClaimableTime);

        (,uint64 claimableTime,,,,,,,,) = idoPool.idoRoundClocks(idoRoundId);
        assertEq(claimableTime, newClaimableTime);

        vm.stopPrank();
    }
    function test_1_6_SetFyTokenMaxBasisPoints() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        uint16 newBasisPoints = 6000; // 60%
        idoPool.setFyTokenMaxBasisPoints(idoRoundId, newBasisPoints);


        (,, uint16 fyTokenMaxBasisPoints,,,,,,,,) = idoPool.idoRoundConfigs(idoRoundId);
        assertEq(fyTokenMaxBasisPoints, newBasisPoints);
        vm.stopPrank();
    }
    function test_1_7_CreateMetaIDO() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        uint64 registrationStartTime = uint64(block.timestamp + 12 hours);
        uint64 registrationEndTime = uint64(block.timestamp + 2 days);

        uint32 metaIdoId = idoPool.createMetaIDO(roundIds, registrationStartTime, registrationEndTime);

        (uint64 storedStartTime, uint64 storedInitialEndTime, uint64 storedEndTime) = idoPool.metaIDOs(metaIdoId);
        assertEq(storedStartTime, registrationStartTime);
        assertEq(storedEndTime, registrationEndTime);
        assertEq(storedInitialEndTime, registrationEndTime);

        vm.stopPrank();
    }
}
