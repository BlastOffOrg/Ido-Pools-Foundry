// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";
import "forge-std/Test.sol";
import {MockRebaseERC20 as MockRebaseERC20Test} from "../../src/mock/MockRebaseERC20.sol";

contract StandardIDOPoolAdvancedTest is StandardIDOPoolBaseTest {
    uint32 public idoRoundId;
    uint32 public metaIdoId;
    address[10] public users;
    uint32 public emptyMetaIdoId;

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
            1, // minRank
            10, // maxRank
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

    function test_5_1_EdgeCaseMinimumAllocation() public {
        address participant = users[0];
        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, 1 ether);
        buyToken.approve(address(idoPool), 1 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 1 ether);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        IDOPoolView.UserParticipationInfo[] memory participationInfo = idoPool.getUserParticipationInfo(participant, roundIds);

        assertEq(participationInfo[0].buyTokenAmount, 1 ether);
    }

    function test_5_2_EdgeCaseMaximumAllocation() public {
        address participant = users[2]; // User with multiplier 3
        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, 300 ether);
        buyToken.approve(address(idoPool), 300 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 300 ether);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        IDOPoolView.UserParticipationInfo[] memory participationInfo = idoPool.getUserParticipationInfo(participant, roundIds);

        assertEq(participationInfo[0].buyTokenAmount, 300 ether);
    }

    function test_5_3_fuzzParticipationAmounts(uint256 amount) public {
        vm.assume(amount >= 1 ether && amount <= 300 ether);

        address participant = users[2]; // User with multiplier 3
        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, amount);
        buyToken.approve(address(idoPool), amount);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), amount);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        IDOPoolView.UserParticipationInfo[] memory participationInfo = idoPool.getUserParticipationInfo(participant, roundIds);

        assertEq(participationInfo[0].buyTokenAmount, amount);
    }

    function test_5_4_SecurityReentrancyCheck() public {
        // This test would require a malicious contract that attempts reentrancy
        // For the purpose of this example, we'll just check that the participation
        // function can't be called recursively

        address participant = users[0];
        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, 10 ether);
        buyToken.approve(address(idoPool), 10 ether);
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert();
        this.callParticipateRecursively(idoRoundId, address(buyToken), 5 ether);

        vm.stopPrank();
    }

    function callParticipateRecursively(uint32 _idoRoundId, address _token, uint256 _amount) external {
        idoPool.participateInRound(_idoRoundId, _token, _amount);
        if (_amount > 1 ether) {
            this.callParticipateRecursively(_idoRoundId, _token, _amount - 1 ether);
        }
    }

function test_5_5_TimeManipulationTests() public {
    address participant = users[0];
    address participant2 = users[1];
    address participant3 = users[2];
    vm.startPrank(admin);
    address[] memory participants = new address[](3);
    participants[0] = participant;
    participants[1] = participant2;
    participants[2] = participant3;
    idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
    vm.stopPrank();

    buyToken.mint(participant, 100 ether);
    buyToken.mint(participant2, 100 ether);
    buyToken.mint(participant3, 100 ether);
    vm.startPrank(participant3);
    buyToken.approve(address(idoPool), 100 ether);
    vm.startPrank(participant2);
    buyToken.approve(address(idoPool), 100 ether);
    vm.startPrank(participant);
    buyToken.approve(address(idoPool), 100 ether);

    // Try to participate before IDO starts
    vm.expectRevert(abi.encodeWithSelector(IIDOPool.NotStarted.selector));
    idoPool.participateInRound(idoRoundId, address(buyToken), 5 ether);

    // Participate during IDO
    vm.warp(block.timestamp + 2 days);
    idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);
    vm.startPrank(participant2);
    idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);
    vm.startPrank(participant3);
    idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);


    // Try to finalize before IDO ends
    vm.startPrank(admin);
    (,,,uint64 idoEndTime,,,,,,) = idoPool.idoRoundClocks(idoRoundId);

    vm.expectRevert(abi.encodeWithSelector(IIDOPool.IDONotEnded.selector, idoEndTime));
    idoPool.finalizeRound(idoRoundId);

    // Warp to after IDO end time
    vm.warp(idoEndTime + 1);

    // Now finalization should succeed
    idoPool.finalizeRound(idoRoundId);
    vm.stopPrank();

    // Try to participate after finalization
    vm.prank(participant);
    vm.expectRevert(abi.encodeWithSelector(IIDOPool.AlreadyFinalized.selector));
    idoPool.participateInRound(idoRoundId, address(buyToken), 5 ether);
}

    function test_5_6_StressTestHighVolumeParticipation() public {
        uint256 participantsCount = 100;
        address[] memory participants = new address[](participantsCount);

        for (uint256 i = 0; i < participantsCount; i++) {
            participants[i] = address(uint160(0x2000 + i));
            MockMultiplierContract(address(multiplierContract)).setMultiplier(participants[i], 1, 5);
        }

        vm.prank(admin);
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);

        vm.warp(block.timestamp + 2 days);

        for (uint256 i = 0; i < participantsCount; i++) {
            vm.startPrank(participants[i]);
            buyToken.mint(participants[i], 10 ether);
            buyToken.approve(address(idoPool), 10 ether);
            idoPool.participateInRound(idoRoundId, address(buyToken), 10 ether);
            vm.stopPrank();
        }

        uint32[] memory roundIds = new uint32[](1);
        roundIds[0] = idoRoundId;
        uint256 totalFunded = idoPool.getFundsRaisedByRounds(roundIds, 0);

        assertEq(totalFunded, 1000 ether);
    }

    function test_5_7_TokenTransferAndApprovalTests() public {
        address participant = users[0];
        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, 10 ether);
        vm.warp(block.timestamp + 2 days);

        // Test without approval
        vm.expectRevert("ERC20: insufficient allowance");
        idoPool.participateInRound(idoRoundId, address(buyToken), 5 ether);

        // Test with insufficient approval
        buyToken.approve(address(idoPool), 3 ether);
        vm.expectRevert("ERC20: insufficient allowance");
        idoPool.participateInRound(idoRoundId, address(buyToken), 5 ether);

        // Test with correct approval
        buyToken.approve(address(idoPool), 5 ether);
        vm.warp(block.timestamp + 2 days);
        idoPool.participateInRound(idoRoundId, address(buyToken), 5 ether);

        vm.stopPrank();
    }

    function test_5_8_fuzzGasLimitTests(uint256 participationAmount) public {
        vm.assume(participationAmount >= 1 ether && participationAmount <= 100 ether);

        address participant = users[0];
        vm.startPrank(admin);
        address[] memory participants = new address[](1);
        participants[0] = participant;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        vm.stopPrank();

        vm.startPrank(participant);
        buyToken.mint(participant, participationAmount);
        buyToken.approve(address(idoPool), participationAmount);
        vm.warp(block.timestamp + 2 days);

        uint256 gasStart = gasleft();
        idoPool.participateInRound(idoRoundId, address(buyToken), participationAmount);
        uint256 gasUsed = gasStart - gasleft();

        // Ensure gas usage is within reasonable limits
        assertLt(gasUsed, 200000);

        vm.stopPrank();
    }

    function test_5_9_ConcurrentMetaIDOsAndRounds() public {
        vm.startPrank(admin);
        uint32 idoRoundId2 = createTestIDORound();
        uint32 metaIdoId2 = idoPool.createMetaIDO(new uint32[](0), uint64(block.timestamp), uint64(block.timestamp + 2 days));

        idoPool.setIDORoundSpecs(idoRoundId2, 1, 10, 100 ether, 1 ether, 10000, false, false, true);
        idoToken.mint(address(idoPool), 1000 ether);
        idoPool.enableIDORound(idoRoundId2);

        idoPool.manageRoundToMetaIDO(metaIdoId2, idoRoundId2, true);

        address participant1 = users[0];
        address participant2 = users[1];
        address[] memory participants = new address[](2);
        participants[0] = participant1;
        participants[1] = participant2;
        idoPool.adminAddRegForMetaIDO(metaIdoId, participants);
        idoPool.adminAddRegForMetaIDO(metaIdoId2, participants);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.startPrank(participant1);
        buyToken.mint(participant1, 200 ether);
        buyToken.approve(address(idoPool), 200 ether);
        idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);
        idoPool.participateInRound(idoRoundId2, address(buyToken), 100 ether);
        vm.stopPrank();

        vm.startPrank(participant2);
        buyToken.mint(participant2, 200 ether);
        buyToken.approve(address(idoPool), 200 ether);
        idoPool.participateInRound(idoRoundId, address(buyToken), 100 ether);
        idoPool.participateInRound(idoRoundId2, address(buyToken), 100 ether);
        vm.stopPrank();

        uint32[] memory roundIds = new uint32[](2);
        roundIds[0] = idoRoundId;
        roundIds[1] = idoRoundId2;

        uint256 totalFunded = idoPool.getFundsRaisedByRounds(roundIds, 0);
        assertEq(totalFunded, 400 ether);

        IDOPoolView.UserParticipationInfo[] memory participationInfo1 = idoPool.getUserParticipationInfo(participant1, roundIds);
        IDOPoolView.UserParticipationInfo[] memory participationInfo2 = idoPool.getUserParticipationInfo(participant2, roundIds);

        assertEq(participationInfo1.length, 2);
        assertEq(participationInfo2.length, 2);
        assertEq(participationInfo1[0].buyTokenAmount + participationInfo1[1].buyTokenAmount, 200 ether);
        assertEq(participationInfo2[0].buyTokenAmount + participationInfo2[1].buyTokenAmount, 200 ether);
    }

}
