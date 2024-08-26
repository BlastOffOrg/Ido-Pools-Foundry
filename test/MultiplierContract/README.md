# MultiplierContract Tests

This folder contains comprehensive tests for the MultiplierContract. 

The tests are split into three files: `MultiplierContractTest.t.sol` for positive,`MultiplierContractFailTest.t.sol` for negative and `MultiplierContractAdvancedTest` for advanced scenarios.

## MultiplierContractTest.t.sol

This file contains tests for the expected behavior of the MultiplierContract.

1. **test_1_InitialSetup**: Verifies that the MultiplierContract is correctly initialized with the right staking contract address and admin.

2. **test_2_ProposeAndExecuteUpdates**: Tests the proposal and execution of level updates. It proposes new levels, thresholds, and multipliers, waits for the timelock period, and then verifies that the update is correctly executed.

3. **test_3_GetMultiplier**: Tests the getMultiplier function with different staking amounts. It sets up levels, stakes tokens, and verifies that the correct multipliers and ranks are returned for different staking amounts.

4. **test_4_UpdateStakingContract**: Tests the update of the staking contract address. It proposes a new staking contract, waits for the timelock period, and then verifies that the update is correctly executed.

5. **test_5_FailNonAdminUpdate**: Tests that non-admin users cannot propose updates. It attempts to propose an update as a non-admin user and expects it to revert.

## MultiplierContractFailTest.t.sol

This file contains tests for scenarios where the MultiplierContract should fail or revert.

1. **testFail_1_ProposeNonConsecutiveLevels**: Tests that proposing non-consecutive levels fails.

2. **testFail_2_ProposeNonIncreasingThresholds**: Tests that proposing non-increasing thresholds fails.

3. **testFail_3_ExecuteUpdatesTooEarly**: Tests that executing updates before the timelock period fails.

4. **testFail_4_UpdateStakingContractToZeroAddress**: Tests that updating the staking contract to the zero address fails.

5. **testFail_5_NonAdminUpdate**: Tests that non-admin users cannot propose updates.

6. **testFail_6_GetMultiplierForNonStaker**: Tests that getting a multiplier for a non-staker fails.

7. **testFail_7_ProposeUpdateWithMismatchedArrayLengths**: Tests that proposing an update with mismatched array lengths fails.

8. **testFail_8_ProposeUpdateWithDecreasingMultipliers**: Tests that proposing an update with decreasing multipliers fails.

9. **testFail_9_ExecuteUpdateWithoutProposal**: Tests that executing an update without a proposal fails.

10. **testFail_10_ProposeEmptyUpdate**: Tests that proposing an empty update fails.

## Advanced Tests

These tests cover edge cases and complex scenarios:

1. **Cancel Proposed Update**: 
   - Tests the ability to cancel a proposed update before execution.
   - Ensures that a cancelled update cannot be executed.

2. **GetMultiplier Edge Cases**: 
   - Tests the `getMultiplier` function with exact threshold amounts.
   - Verifies correct multipliers and ranks for amounts exceeding the highest threshold.

3. **GetMultiplier After Unstake Initiation**: 
   - Checks the behavior when a user initiates unstaking.
   - Ensures that the multiplier and rank return to zero after unstake initiation.

4. **Behavior After Emission End**: 
   - Tests the contract's behavior at and after the emission end time.
   - Verifies that multipliers are still correctly calculated after emissions have ended.

5. **Fuzz Testing GetMultiplier**: 
   - Uses Forge's built-in fuzzing to test `getMultiplier` with various random stake amounts.
   - Ensures correct multiplier and rank calculations across a wide range of inputs.

6. **Maximum Allowed Levels**: 
   - Tests the contract with the maximum allowed number of levels (assumed to be 100 in this test).
   - Verifies correct behavior and calculations with a large number of levels.

These advanced tests help ensure that the MultiplierContract functions correctly under various conditions and edge cases, providing a high level of confidence in the contract's robustness and reliability.
