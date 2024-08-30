// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";
import "forge-std/Test.sol";

contract StandardIDOPoolViewTest is StandardIDOPoolBaseTest {


    uint32 public idoRoundId;
    uint32 public metaIdoId;

    // Local struct to mirror UserMetaIDOInfo
    struct LocalUserMetaIDOInfo {
        uint32 metaIdoId;
        uint16 rank;
        uint16 multiplier;
    }

    // Local struct to mirror UserParticipationInfo
    struct LocalUserParticipationInfo {
        uint32 roundId;
        uint256 fyTokenAmount;
        uint256 buyTokenAmount;
        uint256 idoTokensAllocated;
        uint256 maxAllocation;
    }

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
        idoPool.createMetaIDO(emptyRoundIds, uint64(block.timestamp), uint64(block.timestamp + 1 days));

        // Create second MetaIDO (with our IDO round)
        metaIdoId = idoPool.createMetaIDO(roundIds, uint64(block.timestamp), uint64(block.timestamp + 1 days));

        // Set up IDO round specs
        idoPool.setIDORoundSpecs(idoRoundId, 1, 10, 100 ether, 1 ether, 10000, false, false, true);

        // Enable the IDO round
        idoToken.mint(address(idoPool), 1000 ether);
        idoPool.enableIDORound(idoRoundId);

        // Set ranks and multipliers for users
        MockMultiplierContract(address(multiplierContract)).setMultiplier(user1, 2, 5); // 50% multiplier, rank 5
        MockMultiplierContract(address(multiplierContract)).setMultiplier(user2, 3, 7); // 75% multiplier, rank 7

        // Register users for the MetaIDO
        address[] memory usersToRegister = new address[](2);
        usersToRegister[0] = user1;
        usersToRegister[1] = user2;
        idoPool.adminAddRegForMetaIDO(metaIdoId, usersToRegister);

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
            500 ether,
            5000,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 8 days),
            uint64(block.timestamp + 15 days)
        );
        return idoPool.nextIdoRoundId() - 1;
    }

    function test_4_1_GetParticipantFundingByRounds() public {
        vm.startPrank(user1);
        buyToken.mint(user1, 10 ether);
        buyToken.approve(address(idoPool), 10 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        uint256 fundingAmount = idoPool.getParticipantFundingByRounds(roundIds, user1, 0);
        assertEq(fundingAmount, 10 ether);
    }

    function test_4_2_FuzzGetParticipantFundingByRounds(uint8 tokenType) public {
        vm.assume(tokenType <= 2);

        vm.startPrank(user1);
        buyToken.mint(user1, 10 ether);
        buyToken.approve(address(idoPool), 10 ether);
        fyToken.mint(user1, 5 ether);
        fyToken.approve(address(idoPool), 5 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
        idoPool.participateInRound(idoRoundId, address(fyToken), 5 ether);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        uint256 fundingAmount = idoPool.getParticipantFundingByRounds(roundIds, user1, tokenType);
        if (tokenType == 0) {
            assertEq(fundingAmount, 10 ether);
        } else if (tokenType == 1) {
            assertEq(fundingAmount, 5 ether);
        } else {
            assertEq(fundingAmount, 15 ether);
        }
    }

    function test_4_3_GetFundsRaisedByRounds() public {
        vm.startPrank(user1);
        buyToken.mint(user1, 10 ether);
        buyToken.approve(address(idoPool), 10 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        uint256 fundsRaised = idoPool.getFundsRaisedByRounds(roundIds, 0);
        assertEq(fundsRaised, 10 ether);
    }

    function test_4_4_GetIDORoundsByMetaIDO() public view {
        uint32[] memory roundIds = idoPool.getIDORoundsByMetaIDO(metaIdoId);
        assertEq(roundIds.length, 1);
        assertEq(roundIds[0], idoRoundId);
    }

    function test_4_5_GetMetaIDOByIDORound() public view {
        uint32 retrievedMetaIdoId = idoPool.getMetaIDOByIDORound(idoRoundId);
        assertEq(retrievedMetaIdoId, metaIdoId);
    }

    function test_4_6_GetCheckUserRegisteredForMetaIDO() public view {
        bool isRegistered = idoPool.getCheckUserRegisteredForMetaIDO(user1, metaIdoId);
        assertTrue(isRegistered);
    }

    function test_4_7_GetUserMetaIDOInfo() public view {
        IDOPoolView.UserMetaIDOInfo[] memory contractUserInfo = idoPool.getUserMetaIDOInfo(user1);
        LocalUserMetaIDOInfo[] memory localUserInfo = convertToLocalUserMetaIDOInfo(contractUserInfo);
        
        assertEq(localUserInfo.length, 1);
        assertEq(localUserInfo[0].metaIdoId, metaIdoId);
    }

    function test_4_8_FuzzGetUserParticipationInfo(uint256 participationAmount) public {
        vm.assume(participationAmount > 1 ether && participationAmount <= 100 ether);

        vm.startPrank(user1);
        buyToken.mint(user1, participationAmount);
        buyToken.approve(address(idoPool), participationAmount);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), participationAmount);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;

        IDOPoolView.UserParticipationInfo[] memory contractParticipationInfo = idoPool.getUserParticipationInfo(user1, roundIds);
        LocalUserParticipationInfo[] memory localParticipationInfo = convertToLocalUserParticipationInfo(contractParticipationInfo);

        assertEq(localParticipationInfo.length, 1);
        assertEq(localParticipationInfo[0].roundId, idoRoundId);
        assertEq(localParticipationInfo[0].buyTokenAmount, participationAmount);
    }

    // Helper function to convert contract UserMetaIDOInfo to local struct
    function convertToLocalUserMetaIDOInfo(IDOPoolView.UserMetaIDOInfo[] memory contractInfo) 
        internal 
        pure 
        returns (LocalUserMetaIDOInfo[] memory) 
    {
        LocalUserMetaIDOInfo[] memory localInfo = new LocalUserMetaIDOInfo[](contractInfo.length);
        for (uint i = 0; i < contractInfo.length; i++) {
            localInfo[i] = LocalUserMetaIDOInfo({
                metaIdoId: contractInfo[i].metaIdoId,
                rank: contractInfo[i].rank,
                multiplier: contractInfo[i].multiplier
            });
        }
        return localInfo;
    }

    // Helper function to convert contract UserParticipationInfo to local struct
    function convertToLocalUserParticipationInfo(IDOPoolView.UserParticipationInfo[] memory contractInfo) 
        internal 
        pure 
        returns (LocalUserParticipationInfo[] memory) 
    {
        LocalUserParticipationInfo[] memory localInfo = new LocalUserParticipationInfo[](contractInfo.length);
        for (uint i = 0; i < contractInfo.length; i++) {
            localInfo[i] = LocalUserParticipationInfo({
                roundId: contractInfo[i].roundId,
                fyTokenAmount: contractInfo[i].fyTokenAmount,
                buyTokenAmount: contractInfo[i].buyTokenAmount,
                idoTokensAllocated: contractInfo[i].idoTokensAllocated,
                maxAllocation: contractInfo[i].maxAllocation
            });
        }
        return localInfo;
    }

    function test_4_9_GetUserMaxAlloc() public {
        vm.prank(admin);
        MockMultiplierContract(address(multiplierContract)).setMultiplier(user1, 5000, 5);

        uint256 maxAlloc = idoPool.getUserMaxAlloc(idoRoundId, user1);
        assertEq(maxAlloc, 200 ether); // Assuming 100 ether max alloc with 50% multiplier
    }
}
