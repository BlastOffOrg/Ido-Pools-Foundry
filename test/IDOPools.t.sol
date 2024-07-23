// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/mock/MockERC20.sol";
import {USDIDOPool} from "../src/StandardIDOPool.sol"; // Adjust the import path as needed

contract IDOPoolTest is Test {
    USDIDOPool ido;
    MockERC20 idoToken;
    MockERC20 buyToken;
    MockERC20 fyToken;

    address deployer;
    address user1 = address(1);
    address user2 = address(2);
    address user3 = address(3);
    address user4 = address(4);
    uint256 idoPrice = 1 ether;
    uint256 idoSize = 10_000_000 ether;
    uint256 minimumFundingGoal = 500 ether;
    uint16 fyTokenMaxBasisPoints = 5000; // 50%
    uint64 idoStartTime;
    uint64 idoEndTime;
    uint64 claimableTime;

    function setUp() public {
        deployer = address(0x1);
        idoToken = new MockERC20("IDO Token", "IDOT");
        buyToken = new MockERC20("Buy Token", "BUY");
        fyToken = new MockERC20("FY Token", "FY");

        idoStartTime = uint64(block.timestamp + 1 days);
        idoEndTime = idoStartTime + 1 weeks;
        claimableTime = idoEndTime + 1 days;

        // Deploy your TestIDOPool contract
        vm.startPrank(deployer);
        ido = new USDIDOPool();
        ido.init(deployer);
        vm.stopPrank();

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
        vm.deal(user4, 10 ether);
    }

    function test_CreateNewIDO() public {
        vm.startPrank(deployer);

        uint32 initialIdoRoundId = ido.nextIdoRoundId();

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

        ) = ido.idoRoundClocks(newIdoRoundId);

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
        assertFalse(_hasNoRegList, "IDO should not be have a reg list");
        assertFalse(_isEnabled, "IDO should not be enabled initially");

        (
            address _idoToken,
            uint8 _idoTokenDecimals,
            uint16 _fyTokenMaxBasisPoints,
            address _buyToken,
            address _fyToken,
            uint256 _idoPrice,
            uint256 _idoSize,
            uint256 _idoTokensSold,
            uint256 _minimumFundingGoal,
            uint256 _fundedUSDValue
        ) = ido.idoRoundConfigs(newIdoRoundId);

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

        assertEq(_idoPrice, idoPrice, "IDO price mismatch");
        assertEq(_idoSize, idoSize, "IDO size mismatch");
        assertEq(_idoTokensSold, 0, "IDO tokens sold should be 0");

        assertEq(
            _minimumFundingGoal,
            minimumFundingGoal,
            "Minimum funding goal mismatch"
        );
        assertEq(_fundedUSDValue, 0, "Funded USD value should be 0");

        uint32 metaIdoId = ido.nextMetaIdoId();
        uint32[] memory rounds;
        rounds[0]=initialIdoRoundId;

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

        // Confirm that round is enabled
        (, , , , , , , bool isEnabled, , ) = ido.idoRoundClocks(newIdoRoundId);

        assertTrue(isEnabled, "Round not enabled correctly");

        // Check MetaIDO variables
        /* (
            uint32[] memory roundIds,
            uint64 registrationStartTime,
            uint64 initialRegistrationEndTime,
            uint64 registrationEndTime

        ) = 
            ido.metaIDOs(metaIdoId); */

            console.log(ido.metaIDOs(metaIdoId));
    }

    /*  function test_Participate() public {
        vm.startPrank(deployer);

        uint32 initialIdoRoundId = ido.nextIdoRoundId();

        ido.createIDORound(
            "Test IDO", // IDO name
            address(idoToken),
            address(buyToken),
            address(fyToken),
            idoPrice,
            idoSize,
            minimumFundingGoal,
            fyTokenMaxBasisPoints,
            uint64(block.timestamp),
            uint64(block.timestamp + 7 days),
            uint64(block.timestamp + 8 days)
        );

        // Mint tokens to IDO
        idoToken.mint(address(ido), idoSize);

        //Enable Round and Whitelist
        ido.enableIDORound(initialIdoRoundId);
        //ido.enableHasNoRegList(initialIdoRoundId);

        // Mint buy token to user
        buyToken.mint(user1, 1_000_000 ether);

        vm.stopPrank();

        uint32 newIdoRoundId = initialIdoRoundId;

        vm.startPrank(user1);
        buyToken.approve(address(ido), 1_000_000 ether);
        ido.participateInRound(
            newIdoRoundId,
            address(buyToken),
            1_000_000 ether
        );
    } */
}


