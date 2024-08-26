// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/MultiplierContract.sol";
import "../../src/mock/stakingContract/StakingContract.sol";
import "../../src/mock/stakingContract/BasicToken.sol";

contract MultiplierContractAdvancedTest is Test {
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

    /// @notice Tests canceling a proposed update
    /// @dev Proposes an update, cancels it, and verifies it can't be executed
    function testAdvanced_1_CancelProposedUpdate() public {
        vm.startPrank(admin);

        uint256[] memory levels = new uint256[](1);
        uint256[] memory thresholds = new uint256[](1);
        uint256[] memory multipliers = new uint256[](1);
        levels[0] = 1;
        thresholds[0] = 100 ether;
        multipliers[0] = 10000;

        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        multiplierContract.cancelUpdate();

        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);

        vm.expectRevert("No pending update to execute");
        multiplierContract.executeUpdates();

        vm.stopPrank();
    }

    /// @notice Tests getMultiplier with exact threshold amounts and amounts exceeding the highest threshold
    /// @dev Sets up levels, stakes exact and exceeding amounts, and verifies correct multipliers and ranks
    function testAdvanced_2_GetMultiplierEdgeCases() public {
        vm.startPrank(admin);

        uint256[] memory levels = new uint256[](3);
        uint256[] memory thresholds = new uint256[](3);
        uint256[] memory multipliers = new uint256[](3);
        levels[0] = 1;
        levels[1] = 2;
        levels[2] = 3;
        thresholds[0] = 100 ether;
        thresholds[1] = 200 ether;
        thresholds[2] = 300 ether;
        multipliers[0] = 10000;
        multipliers[1] = 12500;
        multipliers[2] = 15000;

        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);
        multiplierContract.executeUpdates();

        basicToken.transfer(user1, 1000 ether);
        basicToken.transfer(user2, 1000 ether);
        vm.stopPrank();

        // Exact threshold
        vm.startPrank(user1);
        basicToken.approve(address(stakingContract), 200 ether);
        stakingContract.stake(200 ether);
        vm.stopPrank();

        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user1);
        assertEq(multiplier, 12500);
        assertEq(rank, 2);

        // Exceeding highest threshold
        vm.startPrank(user2);
        basicToken.approve(address(stakingContract), 400 ether);
        stakingContract.stake(400 ether);
        vm.stopPrank();

        (multiplier, rank) = multiplierContract.getMultiplier(user2);
        assertEq(multiplier, 15000);
        assertEq(rank, 3);
    }

    /// @notice Tests behavior when a user initiates unstaking
    /// @dev Stakes tokens, waits for minimum staking period, initiates unstaking, and verifies getMultiplier returns 0
    function testAdvanced_3_GetMultiplierAfterUnstakeInitiation() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](1);
        uint256[] memory thresholds = new uint256[](1);
        uint256[] memory multipliers = new uint256[](1);
        levels[0] = 1;
        thresholds[0] = 100 ether;
        multipliers[0] = 10000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);
        multiplierContract.executeUpdates();
        basicToken.transfer(user1, 200 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        basicToken.approve(address(stakingContract), 200 ether);
        stakingContract.stake(200 ether);

        // Wait for the minimum staking period (30 days in this case)
        vm.warp(block.timestamp + 31 days);

        stakingContract.initiateUnstake();
        vm.stopPrank();

        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user1);
        assertEq(multiplier, 0);
        assertEq(rank, 0);
    }

    /// @notice Tests contract behavior at and after emission end time
    /// @dev Sets up staking, waits until after emission end, and checks multiplier
    function testAdvanced_4_BehaviorAfterEmissionEnd() public {
        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](1);
        uint256[] memory thresholds = new uint256[](1);
        uint256[] memory multipliers = new uint256[](1);
        levels[0] = 1;
        thresholds[0] = 100 ether;
        multipliers[0] = 10000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);
        multiplierContract.executeUpdates();
        basicToken.transfer(user1, 200 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        basicToken.approve(address(stakingContract), 200 ether);
        stakingContract.stake(200 ether);
        vm.stopPrank();

        // Warp to after emission end
        vm.warp(block.timestamp + 91 days);

        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user1);
        assertEq(multiplier, 10000);
        assertEq(rank, 1);
    }

    /// @notice Fuzz tests the getMultiplier function with various staked amounts
    /// @dev Uses forge's built-in fuzzing to test getMultiplier with random stake amounts
    function testAdvanced_5_FuzzGetMultiplier(uint256 stakeAmount) public {
        vm.assume(stakeAmount > 0 && stakeAmount <= 1000000 ether);

        vm.startPrank(admin);
        uint256[] memory levels = new uint256[](3);
        uint256[] memory thresholds = new uint256[](3);
        uint256[] memory multipliers = new uint256[](3);
        levels[0] = 1;
        levels[1] = 2;
        levels[2] = 3;
        thresholds[0] = 100 ether;
        thresholds[1] = 200 ether;
        thresholds[2] = 300 ether;
        multipliers[0] = 10000;
        multipliers[1] = 12500;
        multipliers[2] = 15000;
        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);
        multiplierContract.executeUpdates();
        basicToken.transfer(user1, stakeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        basicToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user1);

        if (stakeAmount < 100 ether) {
            assertEq(multiplier, 0);
            assertEq(rank, 0);
        } else if (stakeAmount < 200 ether) {
            assertEq(multiplier, 10000);
            assertEq(rank, 1);
        } else if (stakeAmount < 300 ether) {
            assertEq(multiplier, 12500);
            assertEq(rank, 2);
        } else {
            assertEq(multiplier, 15000);
            assertEq(rank, 3);
        }
    }

    /// @notice Tests with maximum allowed levels
    /// @dev Sets up the maximum number of levels and verifies correct behavior
    function testAdvanced_6_MaximumAllowedLevels() public {
        vm.startPrank(admin);
        uint256 maxLevels = 100; // Assume 100 is the maximum allowed levels
        uint256[] memory levels = new uint256[](maxLevels);
        uint256[] memory thresholds = new uint256[](maxLevels);
        uint256[] memory multipliers = new uint256[](maxLevels);

        for (uint256 i = 0; i < maxLevels; i++) {
            levels[i] = i + 1;
            thresholds[i] = (i + 1) * 100 ether;
            multipliers[i] = 10000 + (i * 100);
        }

        multiplierContract.proposeMultipleUpdates(levels, thresholds, multipliers);
        vm.warp(block.timestamp + multiplierContract.UPDATE_INTERVAL() + 1);
        multiplierContract.executeUpdates();

        basicToken.transfer(user1, 10000 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        basicToken.approve(address(stakingContract), 10000 ether);
        stakingContract.stake(10000 ether);
        vm.stopPrank();

        (uint256 multiplier, uint256 rank) = multiplierContract.getMultiplier(user1);
        assertEq(multiplier, 19900); // 100th level multiplier
        assertEq(rank, 100);
    }

}
