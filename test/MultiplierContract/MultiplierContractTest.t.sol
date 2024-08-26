// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/MultiplierContract.sol";
import "../../src/mock/stakingContract/StakingContract.sol";
import "../../src/mock/stakingContract/BasicToken.sol";

contract MultiplierContractTest is Test {
    MultiplierContract public multiplierContract;
    StakingContract public stakingContract;
    BasicToken public basicToken;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    function setUp() public {
        vm.startPrank(admin);
        
        basicToken = new BasicToken();

        uint256 rewardRate = 100; // tokens per second
        uint256 emissionStart = block.timestamp;
        uint256 emissionDuration = 90 days;
        stakingContract = new StakingContract(
            IERC20(address(basicToken)),
            rewardRate,
            emissionStart,
            emissionDuration
        );

        multiplierContract = new MultiplierContract(address(stakingContract));

        vm.stopPrank();
    }

    /// @notice Verifies that the MultiplierContract is correctly initialized
    /// @dev Checks if the staking contract address and admin are set correctly
    function test_1_InitialSetup() public view {
        assertEq(address(multiplierContract.stakingContract()), address(stakingContract));
        assertEq(multiplierContract.admin(), admin);
    }

    /// @notice Tests the proposal and execution of level updates
    /// @dev Proposes new levels, thresholds, and multipliers, waits for the timelock, and verifies the update
    function test_2_ProposeAndExecuteUpdates() public {
        vm.startPrank(admin);

        uint256[] memory levels = new uint256[](3);
        levels[0] = 1;
        levels[1] = 2;
        levels[2] = 3;

        uint256[] memory thresholds = new uint256[](3);
        thresholds[0] = 100 ether;
        thresholds[1] = 200 ether;
        thresholds[2] = 300 ether;

        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 10000; // 1x
        multipliers[1] = 12500; // 1.25x
        multipliers[2] = 15000; // 1.5x

        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);

        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);

        multiplierContract.executeUpdates();

        assertEq(multiplierContract.maxLevel(), 3);
        assertEq(multiplierContract.levelThresholds(1), 100 ether);
        assertEq(multiplierContract.levelThresholds(2), 200 ether);
        assertEq(multiplierContract.levelThresholds(3), 300 ether);
        assertEq(multiplierContract.levelMultipliers(1), 10000);
        assertEq(multiplierContract.levelMultipliers(2), 12500);
        assertEq(multiplierContract.levelMultipliers(3), 15000);

        vm.stopPrank();
    }

    /// @notice Tests the getMultiplier function with different staking amounts
    /// @dev Sets up levels, stakes tokens, and verifies correct multipliers and ranks
    function test_3_GetMultiplier() public {
			
      	test_2_ProposeAndExecuteUpdates();

        vm.startPrank(admin);
        basicToken.transfer(user1, 1000 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        basicToken.approve(address(stakingContract), 1000 ether);
        stakingContract.stake(150 ether);
        vm.stopPrank();

        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user1);

        assertEq(multiplier, 10000); // 1x multiplier
        assertEq(rank, 1); // Rank 1

        vm.startPrank(user1);
        stakingContract.stake(100 ether);
        vm.stopPrank();

        (multiplier, rank) = multiplierContract.getMultiplier(user1);

        assertEq(multiplier, 12500); // 1.25x multiplier
        assertEq(rank, 2); // Rank 2
    }

    /// @notice Tests the update of the staking contract address
    /// @dev Proposes a new staking contract, waits for the timelock, and verifies the update
    function test_4_UpdateStakingContract() public {
        vm.startPrank(admin);

        StakingContract newStakingContract = new StakingContract(
            IERC20(address(basicToken)),
            100,
            block.timestamp,
            30 days
        );

        multiplierContract.proposeStakingContractUpdate(address(newStakingContract));

        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);

        multiplierContract.executeStakingContractUpdate();

        assertEq(address(multiplierContract.stakingContract()), address(newStakingContract));

        vm.stopPrank();
    }

    /// @notice Tests that non-admin users cannot propose updates
    /// @dev Attempts to propose an update as a non-admin user and expects it to revert
    function test_5_FailNonAdminUpdate() public {
        vm.prank(user1);
        vm.expectRevert("Only admin can perform this action");
        
        uint256[] memory levels = new uint256[](1);
        uint256[] memory thresholds = new uint256[](1);
        uint256[] memory multipliers = new uint256[](1);
        
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
    }
}
