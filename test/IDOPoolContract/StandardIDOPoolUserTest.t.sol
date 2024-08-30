// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";
import "forge-std/Test.sol";

contract StandardIDOPoolUserTest is StandardIDOPoolBaseTest {
    uint32 public idoRoundId;
    uint32 public metaIdoId;
    uint32 public emptyMetaIdoId;

    address[10] public users;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);

        // Create an IDO round
        idoRoundId = createTestIDORound();

        // Create two MetaIDOs
        uint32[] memory emptyRoundIds = new uint32[](0);
        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        // Create first MetaIDO (empty)
        emptyMetaIdoId = idoPool.createMetaIDO(emptyRoundIds, uint64(block.timestamp), uint64(block.timestamp + 1 days));

        // Create second MetaIDO with the IDO round
        metaIdoId = idoPool.createMetaIDO(roundIds, uint64(block.timestamp), uint64(block.timestamp + 1 days));

        // Set up IDO round specs
        idoPool.setIDORoundSpecs(
            idoRoundId,
            3, // minRank
            8, // maxRank
            100 ether, // maxAlloc
            1 ether, // minAlloc
            10000, // maxAllocMultiplier (100%)
            false, // noMultiplier
            false, // noRank
            true // standardMaxAllocMult
        );

        // Enable the IDO round
        idoToken.mint(address(idoPool), 1000 ether);
        idoPool.enableIDORound(idoRoundId);

        // Set up 10 users with different ranks and multipliers
        for (uint i = 0; i < 10; i++) {
            users[i] = address(uint160(0x1000 + i));
            uint256 rank = i + 1;
            uint256 multiplier = (i % 3) + 1; // Multipliers will be 1, 2, or 3
            MockMultiplierContract(address(multiplierContract)).setMultiplier(users[i], multiplier, rank);
        }

        vm.stopPrank();
    }

    function createTestIDORound() internal returns (uint32) {
        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            1 ether,
            1000 ether,
            300 ether,
            5000,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 8 days),
            uint64(block.timestamp + 15 days)
        );
        return idoPool.nextIdoRoundId() - 1;
    }

    function test_3_1_UserRegistration() public {
        for (uint i = 0; i < 10; i++) {
            vm.prank(users[i]);
            idoPool.registerForMetaIDO(metaIdoId);

            bool isRegistered = idoPool.getCheckUserRegisteredForMetaIDO(users[i], metaIdoId);
            assertTrue(isRegistered);

            IDOPoolView.UserMetaIDOInfo[] memory userInfo = idoPool.getUserMetaIDOInfo(users[i]);
            assertEq(userInfo.length, 1);
            assertEq(userInfo[0].metaIdoId, metaIdoId);
            assertEq(userInfo[0].rank, i + 1);
            assertEq(userInfo[0].multiplier, (i % 3) + 1);
        }
    }

    function test_3_2_FuzzUserParticipation(uint256 amount) public {
        vm.assume(amount >= 1 ether && amount <= 200 ether);

        address eligibleUser = users[4]; // User with rank 5 (eligible)

        vm.startPrank(eligibleUser);
        idoPool.registerForMetaIDO(metaIdoId);
        buyToken.mint(eligibleUser, amount);
        buyToken.approve(address(idoPool), amount);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), amount);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        IDOPoolView.UserParticipationInfo[] memory participationInfo = idoPool.getUserParticipationInfo(eligibleUser, roundIds);

        assertEq(participationInfo.length, 1);
        assertEq(participationInfo[0].roundId, idoRoundId);
        assertEq(participationInfo[0].buyTokenAmount, amount);
        assertEq(participationInfo[0].idoTokensAllocated, amount);
    }

    function test_3_3_MultiUserParticipation() public {
        address[] memory eligibleUsers = new address[](6);
        for (uint i = 0; i < 6; i++) {
            eligibleUsers[i] = users[i + 2]; // Users with ranks 3-8
        }

        vm.startPrank(admin);
        idoPool.adminAddRegForMetaIDO(metaIdoId, eligibleUsers);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        for (uint i = 0; i < eligibleUsers.length; i++) {
            address user = eligibleUsers[i];
            uint256 amount = (i + 1) * 10 ether;

            vm.startPrank(user);
            buyToken.mint(user, amount);
            buyToken.approve(address(idoPool), amount);
            idoPool.participateInRound(idoRoundId, address(buyToken), amount);
            vm.stopPrank();
        }

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        uint256 totalFunded = idoPool.getFundsRaisedByRounds(roundIds, 0);
        assertEq(totalFunded, 210 ether); // 10 + 20 + 30 + 40 + 50 + 60 = 210 ether
    }

    function test_3_4_UserClaimIDOTokens() public {
        address claimingUser = users[5]; // User with rank 6 (eligible)

        vm.startPrank(admin);
        address[] memory claimingUsers = new address[](1);
        claimingUsers[0] = claimingUser;
        idoPool.adminAddRegForMetaIDO(metaIdoId, claimingUsers);
        vm.stopPrank();

        vm.startPrank(claimingUser);
        buyToken.mint(claimingUser, 300 ether);
        buyToken.approve(address(idoPool), 300 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 300 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        idoPool.finalizeRound(idoRoundId);

        vm.warp(block.timestamp + 7 days);
        vm.prank(claimingUser);
        idoPool.claimFromRound(idoRoundId, claimingUser);

        assertEq(idoToken.balanceOf(claimingUser), 300 ether);
    }

function test_3_5_UserParticipationWithIneligibleRank() public {
    address lowRankUser = users[0]; // User with rank 1 (below minRank)
    address highRankUser = users[8]; // User with rank 9 (above maxRank)
    address eligibleUser1 = users[4]; // User with rank 5 (within allowed range)
    address eligibleUser2 = users[6]; // User with rank 7 (within allowed range)

    vm.warp(block.timestamp + 2 days);

    // Test 1: Users not registered
    vm.startPrank(lowRankUser);
    buyToken.mint(lowRankUser, 10 ether);
    buyToken.approve(address(idoPool), 10 ether);
    vm.expectRevert(abi.encodeWithSelector(IIDOPool.ParticipantNotRegistered.selector));
    idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
    vm.stopPrank();

    vm.startPrank(highRankUser);
    buyToken.mint(highRankUser, 10 ether);
    buyToken.approve(address(idoPool), 10 ether);
    vm.expectRevert(abi.encodeWithSelector(IIDOPool.ParticipantNotRegistered.selector));
    idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
    vm.stopPrank();

    // Test 2: Users registered
    vm.startPrank(admin);
    address[] memory allUsers = new address[](4);
    allUsers[0] = lowRankUser;
    allUsers[1] = highRankUser;
    allUsers[2] = eligibleUser1;
    allUsers[3] = eligibleUser2;
    idoPool.adminAddRegForMetaIDO(metaIdoId, allUsers);
    vm.stopPrank();

    // Print rank information
    (,uint lowRank) = MockMultiplierContract(address(multiplierContract)).getMultiplier(lowRankUser);
    (,uint highRank) = MockMultiplierContract(address(multiplierContract)).getMultiplier(highRankUser);
    (uint minRank, uint maxRank,,,,,,) = idoPool.idoRoundSpecs(idoRoundId);

    vm.startPrank(lowRankUser);
    vm.expectRevert(abi.encodeWithSelector(IIDOPool.ParticipantRankNotEligible.selector, lowRank, minRank, maxRank));
    idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
    vm.stopPrank();

    console.log("Attempting participation for high rank user (should fail):");
    vm.startPrank(highRankUser);
    vm.expectRevert(abi.encodeWithSelector(IIDOPool.ParticipantRankNotEligible.selector, highRank, minRank, maxRank));
    idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
    vm.stopPrank();

    vm.startPrank(eligibleUser1);
    buyToken.mint(eligibleUser1, 10 ether);
    buyToken.approve(address(idoPool), 10 ether);
    idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
    vm.stopPrank();

    vm.startPrank(eligibleUser2);
    buyToken.mint(eligibleUser2, 10 ether);
    buyToken.approve(address(idoPool), 10 ether);
    idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
    vm.stopPrank();

    // Verify participation
    uint32[] memory roundIds = new uint32[](1);
    roundIds[0] = idoRoundId;
    IDOPoolView.UserParticipationInfo[] memory participationInfo1 = idoPool.getUserParticipationInfo(eligibleUser1, roundIds);
    IDOPoolView.UserParticipationInfo[] memory participationInfo2 = idoPool.getUserParticipationInfo(eligibleUser2, roundIds);

    assert(participationInfo1.length == 1 && participationInfo1[0].buyTokenAmount == 10 ether);
    assert(participationInfo2.length == 1 && participationInfo2[0].buyTokenAmount == 10 ether);

}
    function test_3_6_UserMaxAllocationWithMultiplier() public {
        address[] memory eligibleUsers = new address[](6);
        for (uint i = 0; i < 6; i++) {
            eligibleUsers[i] = users[i + 2]; // Users with ranks 3-8
        }

        vm.startPrank(admin);
        idoPool.adminAddRegForMetaIDO(metaIdoId, eligibleUsers);
        vm.stopPrank();

        for (uint i = 2; i <= 7; i++) { // Users with ranks 3-8 (eligible)
            address user = users[i];
            uint256 maxAlloc = idoPool.getUserMaxAlloc(idoRoundId, user);
            uint256 expectedMaxAlloc = 100 ether * ((i % 3) + 1); // maxAlloc * multiplier
            assertEq(maxAlloc, expectedMaxAlloc, "Incorrect max allocation for user");
        }
    }


    function test_3_7_UserParticipationExceedingMaxAlloc() public {
        address participant = users[5]; // User with rank 6 (eligible)

        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, 400 ether);
        buyToken.approve(address(idoPool), 400 ether);
        vm.warp(block.timestamp + 2 days);

        // Assuming the user has a multiplier of 3 (300 ether max allocation)
        idoPool.participateInRound(idoRoundId, address(buyToken), 250 ether);

        vm.expectRevert(abi.encodeWithSelector(IIDOPool.ContributionTotalAboveMaxAlloc.selector, 350 ether, 300 ether));
        idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);
        vm.stopPrank();
    }

    function test_3_8_EmptyMetaIDOInteractions() public {
        // Try to register for the empty MetaIDO
        vm.prank(users[0]);
        idoPool.registerForMetaIDO(emptyMetaIdoId);

        bool isRegistered = idoPool.getCheckUserRegisteredForMetaIDO(users[0], emptyMetaIdoId);
        assertTrue(isRegistered);

        // Verify that the empty MetaIDO has no associated rounds
        uint32[] memory emptyRoundIds = idoPool.getIDORoundsByMetaIDO(emptyMetaIdoId);
        assertEq(emptyRoundIds.length, 0);
    }

    function test_3_9_MultipleUsersWithDifferentRanksAndMultipliers() public {
        address[] memory eligibleUsers = new address[](6);
        for (uint i = 0; i < 6; i++) {
            eligibleUsers[i] = users[i + 2]; // Users with ranks 3-8
        }

        vm.startPrank(admin);
        idoPool.adminAddRegForMetaIDO(metaIdoId, eligibleUsers);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        for (uint i = 0; i < eligibleUsers.length; i++) {
            address user = eligibleUsers[i];
            uint256 multiplier = (i % 3) + 1;
            uint256 maxAlloc = 100 ether * multiplier;
            uint256 participationAmount = maxAlloc / 2; // Participate with half of max allocation

            vm.startPrank(user);
            buyToken.mint(user, participationAmount);
            buyToken.approve(address(idoPool), participationAmount);
            idoPool.participateInRound(idoRoundId, address(buyToken), participationAmount);
            vm.stopPrank();
        }

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        for (uint i = 0; i < eligibleUsers.length; i++) {
            address user = eligibleUsers[i];
            IDOPoolView.UserParticipationInfo[] memory participationInfo = idoPool.getUserParticipationInfo(user, roundIds);

            uint256 multiplier = (i % 3) + 1;
            uint256 expectedParticipation = 50 ether * multiplier;
            assertEq(participationInfo[0].buyTokenAmount, expectedParticipation);
        }
    }

    function test_3_10_UserRefundAfterCanceledIDO() public {
        address participant = users[4]; // User with rank 5 (eligible)

        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, 50 ether);
        buyToken.approve(address(idoPool), 50 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 50 ether);
        vm.stopPrank();

        vm.prank(admin);
        idoPool.cancelIDORound(idoRoundId);

        uint256 initialBalance = buyToken.balanceOf(participant);
        vm.prank(participant);
        idoPool.claimRefund(idoRoundId);
        uint256 finalBalance = buyToken.balanceOf(participant);

        assertEq(finalBalance - initialBalance, 50 ether);
    }
}
