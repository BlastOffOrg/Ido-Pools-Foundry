// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/MultiplierContract.sol";
import "../../src/mock/stakingContract/StakingContract.sol";
import "../../src/mock/stakingContract/BasicToken.sol";

contract MultiplierContractFailTest is Test {
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

    /// @notice Tests that proposing non-consecutive levels fails
    /// @dev Attempts to propose levels 1, 3, 4 which are not consecutive
    function testFail_1_ProposeNonConsecutiveLevels() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](3);
        levels[0] = 1;
        levels[1] = 3; // Non-consecutive
        levels[2] = 4;
        uint256[] memory thresholds = new uint256[](3);
        thresholds[0] = 100 ether;
        thresholds[1] = 200 ether;
        thresholds[2] = 300 ether;
        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 10000;
        multipliers[1] = 12500;
        multipliers[2] = 15000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.stopPrank();
    }

    /// @notice Tests that proposing non-increasing thresholds fails
    /// @dev Attempts to propose thresholds that are not strictly increasing
    function testFail_2_ProposeNonIncreasingThresholds() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](3);
        levels[0] = 1;
        levels[1] = 2;
        levels[2] = 3;
        uint256[] memory thresholds = new uint256[](3);
        thresholds[0] = 100 ether;
        thresholds[1] = 90 ether; // Not increasing
        thresholds[2] = 110 ether;
        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 10000;
        multipliers[1] = 12500;
        multipliers[2] = 15000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.stopPrank();
    }

    /// @notice Tests that executing updates before the timelock period fails
    /// @dev Attempts to execute updates immediately after proposing them
    function testFail_3_ExecuteUpdatesTooEarly() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](1);
        levels[0] = 1;
        uint256[] memory thresholds = new uint256[](1);
        thresholds[0] = 100 ether;
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 10000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        multiplierContract.executeUpdates(); // Should fail because timelock hasn't passed
        vm.stopPrank();
    }

    /// @notice Tests that updating the staking contract to the zero address fails
    /// @dev Attempts to update the staking contract address to address(0)
    function testFail_4_UpdateStakingContractToZeroAddress() public {
        vm.startPrank(admin);
        multiplierContract.proposeStakingContractUpdate(address(0));
        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);
        multiplierContract.executeStakingContractUpdate();
        vm.stopPrank();
    }

    /// @notice Tests that non-admin users cannot propose updates
    /// @dev Attempts to propose an update from a non-admin account
    function testFail_5_NonAdminUpdate() public {
        vm.prank(user1);
        uint256[] memory levels = new uint256[](1);
        levels[0] = 1;
        uint256[] memory thresholds = new uint256[](1);
        thresholds[0] = 100 ether;
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 10000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
    }

    /// @notice Tests that getting a multiplier for a non-staker fails
    /// @dev Attempts to get a multiplier for an address that hasn't staked
    function testFail_6_GetMultiplierForNonStaker() public {
        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user2);
        require(multiplier != 0 || rank != 0, "Expected to fail for non-staker");
    }

    /// @notice Tests that proposing an update with mismatched array lengths fails
    /// @dev Attempts to propose an update with different lengths for levels, thresholds, and multipliers
    function testFail_7_ProposeUpdateWithMismatchedArrayLengths() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](2);
        levels[0] = 1;
        levels[1] = 2;
        uint256[] memory thresholds = new uint256[](2);
        thresholds[0] = 100 ether;
        thresholds[1] = 200 ether;
        uint256[] memory multipliers = new uint256[](3); // Mismatched length
        multipliers[0] = 10000;
        multipliers[1] = 12500;
        multipliers[2] = 15000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.stopPrank();
    }

    /// @notice Tests that proposing an update with decreasing multipliers fails
    /// @dev Attempts to propose multipliers that are not non-decreasing
    function testFail_8_ProposeUpdateWithDecreasingMultipliers() public {
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
        multipliers[0] = 15000;
        multipliers[1] = 12500; // Decreasing
        multipliers[2] = 10000; // Decreasing
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.stopPrank();
    }

    /// @notice Tests that executing an update without a proposal fails
    /// @dev Attempts to execute updates without proposing them first
    function testFail_9_ExecuteUpdateWithoutProposal() public {
        vm.prank(admin);
        multiplierContract.executeUpdates();
    }

    /// @notice Tests that proposing an empty update fails
    /// @dev Attempts to propose an update with empty arrays
    function testFail_10_ProposeEmptyUpdate() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](0);
        uint256[] memory thresholds = new uint256[](0);
        uint256[] memory multipliers = new uint256[](0);
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.stopPrank();
    }
}
