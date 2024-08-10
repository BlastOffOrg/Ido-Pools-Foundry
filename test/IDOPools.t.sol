// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/mock/MockERC20.sol";
import "./helpers/TestStandardIDOPool.sol";
import "forge-std/console.sol";


contract IDOPoolTest is Test {
    TestStandardIDOPool ido;
    MockERC20 idoToken;
    MockERC20 buyToken;
    MockERC20 fyToken;

    error NotStarted();
    error IDONotEnded();

    address deployer;
    address user1 = address(1);
    address user2 = address(2);
    address user3 = address(3);
    address user4 = address(4);
    uint256 idoPrice = 1 ether;
    uint256 idoSize = 1_000_000 ether;
    uint256 minimumFundingGoal = 500_000 ether;
    uint16 fyTokenMaxBasisPoints = 5000; // 50%
    uint64 idoStartTime;
    uint64 idoEndTime;
    uint64 claimableTime;

    function setUp() public {
        deployer = address(this);
        idoToken = new MockERC20("IDO Token", "IDOT");
        buyToken = new MockERC20("Buy Token", "BUY");
        fyToken = new MockERC20("FY Token", "FY");

        idoStartTime = uint64(block.timestamp + 1 days);
        idoEndTime = idoStartTime + 1 weeks;
        claimableTime = idoEndTime + 1 days;

        // Deploy TestStandardIDOPool contract
        vm.startPrank(deployer);
        ido = new TestStandardIDOPool();
        ido.init(deployer, address(0x2));
        vm.stopPrank();

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(user4, 10 ether);

    }


    function _setIDORoundSpecs(uint32 idoRoundId) internal {
        vm.startPrank(deployer);
        ido.setIDORoundSpecs(
            idoRoundId,
            1, // minRank
            10, // maxRank
            1000 ether, // maxAlloc
            1 ether, // minAlloc
            10000, // maxAllocMultiplier (100% in basis points)
            false, // noMultiplier
            false, // noRank
            true // standardMaxAllocMult
        );
        vm.stopPrank();
    }

    function _verifyIDORoundConfig(uint32 newIdoRoundId) internal view {
        (
            address _idoToken,
            uint8 _idoTokenDecimals,
            uint16 _fyTokenMaxBasisPoints,
            address _buyToken,
            address _fyToken
        ) = ido.getIDORoundConfigPart1(newIdoRoundId);

        assertEq(_idoToken, address(idoToken), "IDO token address mismatch");
        assertEq(_buyToken, address(buyToken), "Buy token address mismatch");
        assertEq(_fyToken, address(fyToken), "FY token address mismatch");
        assertEq(
            _fyTokenMaxBasisPoints,
            fyTokenMaxBasisPoints,
            "FY token max basis points mismatch"
        );
        assertEq(
            _idoTokenDecimals,
            idoToken.decimals(),
            "IDO token decimals mismatch"
        );

        (
            uint256 _idoPrice,
            uint256 _idoSize,
            uint256 _idoTokensSold,
            uint256 _minimumFundingGoal,
            uint256 _fundedUSDValue
        ) = ido.getIDORoundConfigPart2(newIdoRoundId);

        assertEq(_idoPrice, idoPrice, "IDO price mismatch");
        assertEq(_idoSize, idoSize, "IDO size mismatch");
        assertEq(_idoTokensSold, 0, "IDO tokens sold should be 0");
        assertEq(
            _minimumFundingGoal,
            minimumFundingGoal,
            "Minimum funding goal mismatch"
        );
        assertEq(_fundedUSDValue, 0, "Funded USD value should be 0");
    }

    function _verifyMetaIDOCreation(
        uint32 initialIdoRoundId,
        uint32 metaIdoId
    ) internal view {
        // Confirm that round is enabled
        (, , , , , , , bool isEnabled, , ) = ido.getIDORoundClock(
            initialIdoRoundId
        );
        assertTrue(isEnabled, "Round not enabled correctly");

        // Check MetaIDO variables
        (
            uint64 registrationStartTime,
            uint64 initialRegistrationEndTime,
            uint64 registrationEndTime
        ) = ido.getMetaIDOInfo(metaIdoId);

        assertEq(
            registrationStartTime,
            uint64(block.timestamp),
            "Registration start time mismatch"
        );
        assertEq(
            registrationEndTime,
            uint64(block.timestamp + 12 hours),
            "Registration end time mismatch"
        );
        assertEq(
            initialRegistrationEndTime,
            registrationEndTime,
            "Initial registration end time mismatch"
        );

        uint32[] memory metaIDORounds = ido.getIDORoundsByMetaIDO(metaIdoId);
        assertEq(metaIDORounds.length, 1, "MetaIDO should have 1 round");
        assertEq(
            metaIDORounds[0],
            initialIdoRoundId,
            "MetaIDO round ID mismatch"
        );
    }

    function test_CreateNewIDO() public {
        console.log("Caller at start of test test_Create:", msg.sender);
        vm.startPrank(deployer);

        uint32 initialIdoRoundId = ido.nextIdoRoundId();
        console.log("Caller 2 at start of test test_Create:", msg.sender);

        ido.createIDORound(
            "Test IDO", // IDO name
            address(idoToken),
            address(buyToken),
            address(fyToken),
            idoPrice,
            idoSize,
            minimumFundingGoal,
            fyTokenMaxBasisPoints,
            idoStartTime,
            idoEndTime,
            claimableTime
        );
        console.log("Caller 3 at start of test test_Create:", msg.sender);

        _setIDORoundSpecs(initialIdoRoundId);

        vm.stopPrank();

        uint32 newIdoRoundId = initialIdoRoundId;

        // Verify the IDO was created correctly
        assertEq(
            ido.nextIdoRoundId(),
            initialIdoRoundId + 1,
            "IDO Round ID not incremented correctly"
        );

        // Check IDORoundClock
        (
            uint64 _idoStartTime,
            uint64 _claimableTime,
            uint64 _initialClaimableTime,
            uint64 _idoEndTime,
            uint64 _initialIdoEndTime,
            bool _isFinalized,
            bool _isCanceled,
            bool _isEnabled,
            bool _hasNoRegList,

        ) = ido.getIDORoundClock(newIdoRoundId);

        assertEq(_idoStartTime, idoStartTime, "IDO start time mismatch");
        assertEq(_idoEndTime, idoEndTime, "IDO end time mismatch");
        assertEq(_claimableTime, claimableTime, "Claimable time mismatch");
        assertEq(
            _initialClaimableTime,
            claimableTime,
            "Initial claimable time mismatch"
        );
        assertEq(
            _initialIdoEndTime,
            idoEndTime,
            "Initial IDO end time mismatch"
        );
        assertFalse(_isFinalized, "IDO should not be finalized");
        assertFalse(_isCanceled, "IDO should not be cancelled");
        assertFalse(_hasNoRegList, "IDO should not have a reg list");
        assertFalse(_isEnabled, "IDO should not be enabled initially");

        // Check IDORoundConfig
        _verifyIDORoundConfig(newIdoRoundId);

        uint32 metaIdoId = ido.nextMetaIdoId();
        uint32[] memory rounds = new uint32[](1);
        rounds[0] = initialIdoRoundId;

        // Send tokens to IDO contract and enable IDO round
        vm.startPrank(deployer);
        idoToken.mint(address(ido), idoSize);
        ido.enableIDORound(initialIdoRoundId);
        ido.createMetaIDO(
            rounds,
            uint64(block.timestamp),
            uint64(block.timestamp + 12 hours)
        );
        vm.stopPrank();

        _verifyMetaIDOCreation(initialIdoRoundId, metaIdoId);
    }

    function test_Multi_Round_IDO() public {
        vm.startPrank(deployer);

        uint32 roundOne = ido.nextIdoRoundId();

        // THREE ROUNDS OF 1M TOKENS EACH

        ido.createIDORound(
            "One IDO", // IDO name
            address(idoToken),
            address(buyToken),
            address(fyToken),
            idoPrice,
            1000000 * 10 ** 18,
            minimumFundingGoal,
            fyTokenMaxBasisPoints,
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 2 days),
            uint64(block.timestamp + 3 days)
        );
        _setIDORoundSpecs(roundOne);

        uint32 roundTwo = ido.nextIdoRoundId();

        ido.createIDORound(
            "Two IDO", // IDO name
            address(idoToken),
            address(buyToken),
            address(fyToken),
            idoPrice,
            1000000 * 10 ** 18,
            minimumFundingGoal,
            fyTokenMaxBasisPoints,
            uint64(block.timestamp + 3 days),
            uint64(block.timestamp + 4 days),
            uint64(block.timestamp + 5 days)
        );
        _setIDORoundSpecs(roundTwo);

        uint32 roundThree = ido.nextIdoRoundId();
        ido.createIDORound(
            "Three IDO", // IDO name
            address(idoToken),
            address(buyToken),
            address(fyToken),
            idoPrice,
            1000000 * 10 ** 18,
            minimumFundingGoal,
            fyTokenMaxBasisPoints,
            uint64(block.timestamp + 6 days),
            uint64(block.timestamp + 7 days),
            uint64(block.timestamp + 8 days)
        );
        _setIDORoundSpecs(roundThree);

        // Create META IDO
        uint32[] memory rounds = new uint32[](3);
        rounds[0] = roundOne;
        rounds[1] = roundTwo;
        rounds[2] = roundThree;
        (uint32 metaIdoId)= ido.createMetaIDO(
            rounds,
            uint64(block.timestamp),
            uint64(block.timestamp + 12 hours)
        );
        assertEq(1, metaIdoId);

        // Mint tokens to IDO
        idoToken.mint(address(ido), idoSize);

        //Enable Round and Whitelist
        ido.enableIDORound(roundOne);
        vm.expectRevert("Insufficient tokens in contract for all enabled IDOs");
        ido.enableIDORound(roundTwo);
        idoToken.mint(address(ido), idoSize * 2);
        ido.enableIDORound(roundThree);
        ido.enableHasNoRegList(roundOne);
        ido.enableHasNoRegList(roundTwo);
        ido.enableHasNoRegList(roundThree);

        // Mint buy token to user
        buyToken.mint(user1, 2_000_000 ether);
        buyToken.mint(user2, 2_000_000 ether);

        vm.stopPrank();

        (uint32[] memory metaIDORounds) = ido.getIDORoundsByMetaIDO(metaIdoId);

        assert(metaIDORounds[0]==1);
        assert(metaIDORounds[1]==2);
        assert(metaIDORounds[2]==3);
    }
}

