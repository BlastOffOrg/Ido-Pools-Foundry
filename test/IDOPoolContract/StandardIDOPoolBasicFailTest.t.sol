// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";

contract StandardIDOPoolFailTest is StandardIDOPoolBaseTest {

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

    function testFail_1_1_NonAdminInitialSetup() public {
        vm.prank(user1);
        // This should fail as user1 is not the admin
        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            1 ether,
            1000 ether,
            500 ether,
            5000,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 8 days),
            uint64(block.timestamp + 15 days)
        );
    }

    function testFail_1_2_CreateIDORoundWithInvalidTimes() public {
        vm.prank(admin);
        // This should fail as the end time is before the start time
        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            1 ether,
            1000 ether,
            500 ether,
            5000,
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 1 days), // End time before start time
            uint64(block.timestamp + 3 days)
        );
    }

    function testFail_1_3_EnableIDORoundWithoutSpecs() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        // Try to enable the IDO round without setting specs
        idoPool.enableIDORound(idoRoundId);
        vm.stopPrank();
    }

    function testFail_1_4_DelayIdoEndTimeTooMuch() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();
        // Get the initial end time
        (,,,uint64 initialIdoEndTime,,,,,,) = idoPool.idoRoundClocks(idoRoundId);

        // Try to delay by more than 2 weeks
        uint64 newEndTime = initialIdoEndTime + 2 weeks + 1 seconds;
        idoPool.delayIdoEndTime(idoRoundId, newEndTime);


        vm.stopPrank();
    }

    function testFail_1_5_DelayClaimableTimeBeforeEndTime() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        // Try to set claimable time before the IDO end time
        uint64 newClaimableTime = uint64(block.timestamp + 7 days);
        idoPool.delayClaimableTime(idoRoundId, newClaimableTime);

        vm.stopPrank();
    }

    function testFail_1_6_SetFyTokenMaxBasisPointsTooHigh() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        // Try to set basis points higher than 10000 (100%)
        uint16 newBasisPoints = 11000;
        idoPool.setFyTokenMaxBasisPoints(idoRoundId, newBasisPoints);

        vm.stopPrank();
    }

    function testFail_1_7_CreateMetaIDOWithInvalidTimes() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        // Try to create MetaIDO with end time before start time
        uint64 registrationStartTime = uint64(block.timestamp + 2 days);
        uint64 registrationEndTime = uint64(block.timestamp + 1 days);

        idoPool.createMetaIDO(roundIds, registrationStartTime, registrationEndTime);

        vm.stopPrank();
    }
}
