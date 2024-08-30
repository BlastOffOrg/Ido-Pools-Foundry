// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";
import "forge-std/Test.sol";

contract StandardIDOPoolAdminTest is StandardIDOPoolBaseTest {

    function setUp() public override {
        super.setUp();
    }

    function createTestIDORound() internal returns (uint32) {
        return createTestIDORound(1 ether, 1000 ether, 100 ether, 5000);
    }

    function createTestIDORound(uint256 idoPrice, uint256 idoSize, uint256 minimumFundingGoal, uint16 fyTokenMaxBasisPoints) internal returns (uint32) {
        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            idoPrice,
            idoSize,
            minimumFundingGoal,
            fyTokenMaxBasisPoints,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 8 days),
            uint64(block.timestamp + 15 days)
        );
        return idoPool.nextIdoRoundId() - 1;
    }

    function test_2_1_AdminOwnership() public {
        assertEq(idoPool.owner(), admin);
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        idoPool.createIDORound("Test", address(0), address(0), address(0), 0, 0, 0, 0, 0, 0, 0);
    }

function test_2_2_FinalizeRound() public {
    vm.startPrank(admin);
    
    // Create and set up the IDO round
    uint32 idoRoundIdOne = createTestIDORound();
    uint32 idoRoundId = createTestIDORound();


    idoPool.setIDORoundSpecs(
        idoRoundId,
        0, // minRank
        10, // maxRank
        100 ether, // maxAlloc
        1 ether, // minAlloc
        10000, // maxAllocMultiplier (100%)
        true, // noMultiplier
        false, // noRank
        true // standardMaxAllocMult
    );
    idoToken.mint(address(idoPool), 1000 ether);
    idoPool.enableIDORound(idoRoundId);

    // Create a MetaIDO and add the round to it
    uint32[] memory roundIdsOne = new uint32[](1);
    uint32[] memory roundIds = new uint32[](1);
    roundIdsOne[0] = idoRoundIdOne;
    roundIds[0] = idoRoundId;
    uint64 registrationStartTime = uint64(block.timestamp);
    uint64 registrationEndTime = uint64(block.timestamp + 12 hours);
    // blank round created
    idoPool.createMetaIDO(roundIdsOne, registrationStartTime, registrationEndTime);
    uint32 metaIdoId = idoPool.createMetaIDO(roundIds, registrationStartTime, registrationEndTime);

    vm.stopPrank();

    // Register user1 for the MetaIDO
    vm.prank(user1);
    idoPool.registerForMetaIDO(metaIdoId);

    // Advance time to after the IDO start time
    vm.warp(block.timestamp + 2 days);

    // Simulate some participation
    vm.startPrank(user1);
    buyToken.mint(user1, 100 ether);
    buyToken.approve(address(idoPool), 100 ether);
    idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);
    vm.stopPrank();

    // Warp to after IDO end time
    vm.warp(block.timestamp + 9 days);

    // Finalize the round
    vm.prank(admin);
    idoPool.finalizeRound(idoRoundId);

    // Check if the round is finalized
    (,,,,,,bool isFinalized,,,) = idoPool.idoRoundClocks(idoRoundId);
    assertTrue(isFinalized);
}

    function test_2_3_CancelIDORound() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();
        idoPool.cancelIDORound(idoRoundId);
        vm.stopPrank();

        (,,,,,, bool isFinalized, bool isCanceled,,) = idoPool.idoRoundClocks(idoRoundId);
        assertTrue(isCanceled);
        assertFalse(isFinalized);
    }

    function test_2_4_EnableHasNoRegList() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();
        idoPool.enableHasNoRegList(idoRoundId);
        vm.stopPrank();

        (,,,,,,,,, bool hasNoRegList) = idoPool.idoRoundClocks(idoRoundId);
        assertTrue(hasNoRegList);
    }

    function testFuzz_2_5_CreateIDORound(uint256 idoPrice, uint256 idoSize, uint256 minimumFundingGoal, uint16 fyTokenMaxBasisPoints) public {
        vm.assume(idoPrice > 0 && idoPrice < 1e30);
        vm.assume(idoSize > 0 && idoSize < 1e30);
        vm.assume(minimumFundingGoal > 0 && minimumFundingGoal <= idoSize * idoPrice / 1e18);
        vm.assume(fyTokenMaxBasisPoints <= 10000);

        vm.prank(admin);
        uint32 idoRoundId = createTestIDORound(idoPrice, idoSize, minimumFundingGoal, fyTokenMaxBasisPoints);

        (,,,,, uint256 configIdoPrice, uint256 configIdoSize,,, uint256 configMinimumFundingGoal,) = idoPool.idoRoundConfigs(idoRoundId);
        assertEq(configIdoPrice, idoPrice);
        assertEq(configIdoSize, idoSize);
        assertEq(configMinimumFundingGoal, minimumFundingGoal);
    }

    function test_2_6_AdminAddRegForMetaIDO() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();
        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        uint32 metaIdoId = idoPool.createMetaIDO(roundIds, uint64(block.timestamp), uint64(block.timestamp + 1 days));

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        idoPool.adminAddRegForMetaIDO(metaIdoId, users);
        vm.stopPrank();

        assertTrue(idoPool.getCheckUserRegisteredForMetaIDO(user1, metaIdoId));
        assertTrue(idoPool.getCheckUserRegisteredForMetaIDO(user2, metaIdoId));
    }

    function test_2_7_AdminRemoveRegForMetaIDO() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();
        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        uint32 metaIdoId = idoPool.createMetaIDO(roundIds, uint64(block.timestamp), uint64(block.timestamp + 1 days));

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        idoPool.adminAddRegForMetaIDO(metaIdoId, users);
        
        idoPool.adminRemoveRegForMetaIDO(metaIdoId, users);
        vm.stopPrank();

        assertFalse(idoPool.getCheckUserRegisteredForMetaIDO(user1, metaIdoId));
        assertFalse(idoPool.getCheckUserRegisteredForMetaIDO(user2, metaIdoId));
    }

    function test_2_8_WithdrawSpareIDO() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound(1 ether, 1000 ether, 500 ether, 5000);
        idoToken.mint(address(idoPool), 2000 ether); // Mint extra tokens
        idoPool.setIDORoundSpecs(idoRoundId, 1, 10, 100 ether, 1 ether, 10000, false, false, true);
        idoPool.enableIDORound(idoRoundId);
        
        uint256 initialBalance = idoToken.balanceOf(admin);
        idoPool.withdrawSpareIDO(idoRoundId);
        uint256 finalBalance = idoToken.balanceOf(admin);
        
        assertEq(finalBalance - initialBalance, 1000 ether);
        vm.stopPrank();
    }

    function test_2_9_DelayMetaIDORegEndTime() public {
        vm.startPrank(admin);
        uint32 idoRoundId = createTestIDORound();
        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        uint64 initialEndTime = uint64(block.timestamp + 1 days);
        uint32 metaIdoId = idoPool.createMetaIDO(roundIds, uint64(block.timestamp), initialEndTime);

        uint64 newEndTime = initialEndTime + 1 days;
        idoPool.delayMetaIDORegEndTime(metaIdoId, newEndTime);
        vm.stopPrank();

        (, uint64 storedInitialEndTime, uint64 storedEndTime) = idoPool.metaIDOs(metaIdoId);
        assertEq(storedEndTime, newEndTime);
        assertEq(storedInitialEndTime, initialEndTime);
    }

    function test_2_10_ProposeAndExecuteMultiplierContractUpdate() public {
        vm.startPrank(admin);
        address newMultiplierContract = address(new MockMultiplierContract());
        idoPool.proposeMultiplierContractUpdate(newMultiplierContract);
        
        // Warp time to after the update delay
        vm.warp(block.timestamp + idoPool.MULTIPLIER_UPDATE_DELAY() + 1);
        
        idoPool.executeMultiplierContractUpdate();
        vm.stopPrank();

        assertEq(address(idoPool.multiplierContract()), newMultiplierContract);
    }
}
