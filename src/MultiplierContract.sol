// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakingContract {
    /// @notice Retrieves staking details for a given user.
    /// @param user The address of the user to query.
    /// @return amountStaked The amount staked by the user.
    /// @return rewardDebt The debt of the user towards rewards.
    /// @return rewards The total rewards accumulated by the user.
    /// @return unstakeInitTime The timestamp when unstaking was initiated.
    /// @return stakeInitTime The timestamp when staking was initiated.
    function stakers(address user) external view returns (
        uint256 amountStaked, 
        uint256 rewardDebt, 
        uint256 rewards, 
        uint256 unstakeInitTime, 
        uint256 stakeInitTime
    );
}

/// @title Interface for the Multiplier Contract
/// @notice This interface defines the core functionality for retrieving user multipliers and ranks
interface IMultiplierContract {
    /// @notice Retrieves the multiplier and rank for a given user
    /// @param user The address of the user to query
    /// @return multiplier The multiplier value corresponding to the user's staked amount. In integers, 1x,2x,3x,...
    /// @return rank The rank or level that corresponds to the user's staked amount
    function getMultiplier(address user) external view returns (uint256 multiplier, uint256 rank);
}

/// @title Multiplier Contract for managing levels and multipliers based on staked amounts.
/// @notice This contract allows for timed updates to multiplier and threshold configurations based on user stakings.
contract MultiplierContract {
    address public admin;
    uint256 public constant UPDATE_INTERVAL = 1 minutes; // The time interval after which updates can be executed.
    uint256 public maxLevel; 

    IStakingContract public stakingContract;
    address public proposedStakingContract;
    uint256 public stakingContractUpdateUnlockTime;

    // Maps a level to its threshold
    mapping(uint256 => uint256) public levelThresholds;
    // Maps a level to its multiplier
    mapping(uint256 => uint256) public levelMultipliers;

    struct TimelockedUpdate {
        uint256[] levels;
        uint256[] thresholds;
        uint256[] multipliers;
        uint256 unlockTime;
        bool pending;
    }

    TimelockedUpdate public pendingUpdate;

    event UpdateProposed(uint256 unlockTime);
    event UpdateExecuted();
    event UpdateCancelled();
    event StakingContractUpdateProposed(address proposedAddress, uint256 unlockTime);
    event StakingContractUpdated(address newAddress);
    event StakingContractUpdateCancelled(address cancelledAddress);

    /// @notice Initializes the contract with a staking contract address.
    /// @param _stakingContractAddress The address of the staking contract.
    constructor(address _stakingContractAddress) {
        stakingContract = IStakingContract(_stakingContractAddress);
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    /// @notice Proposes a new set of level configurations for thresholds and multipliers with a timelock.
    /// @dev This function initializes a timelocked update which must pass the duration before being executed.
    ///      Each array of levels, thresholds, and multipliers must be sorted in strictly ascending order
    ///      and match in length. Levels must increment by 1 without gaps.
    /// @param levels An array of consecutive integer levels starting from any integer greater than zero. Value is in integer. 1,2,3,...
    /// @param thresholds An array of thresholds corresponding to each level, must be strictly increasing. Value is in wei.
    /// @param multipliers An array of multipliers corresponding to each level, must be non-decreasing. Value is in integer. 1,2,3,...
    /// @custom:security onlyAdmin This function can only be called by the admin.
    function proposeMultipleUpdates(uint256[] calldata levels, uint256[] calldata thresholds, uint256[] calldata multipliers) external onlyAdmin {
        require(!pendingUpdate.pending, "There is already a pending update");
        require(levels.length == thresholds.length && thresholds.length == multipliers.length, "Array lengths must match");
        require(levels.length > 0, "Arrays cannot be empty");

        for (uint256 i = 1; i < levels.length; i++) {
            require(levels[i] == levels[i - 1] + 1, "Levels must be consecutive integers");
            require(thresholds[i] > thresholds[i - 1], "Thresholds array must be strictly increasing");
            require(multipliers[i] >= multipliers[i - 1], "Multipliers array must be equal or increasing");
        }

        pendingUpdate = TimelockedUpdate({
            levels: levels,
            thresholds: thresholds,
            multipliers: multipliers,
            unlockTime: block.timestamp + UPDATE_INTERVAL,
            pending: true
        });

        emit UpdateProposed(pendingUpdate.unlockTime);
    }

    /// @notice Cancels the pending updates to levels, thresholds, and multipliers.
    function cancelUpdate() external onlyAdmin {
        require(pendingUpdate.pending, "No pending update to cancel");
        delete pendingUpdate;
        emit UpdateCancelled();
    }

    /// @notice Executes the pending updates to levels, thresholds, and multipliers after the timelock period has passed.
    /// @dev Clears all previous data up to the previous maximum level and applies new configurations.
    ///      This action is irreversible and takes effect immediately once executed.
    /// @custom:security onlyAdmin This function can only be called by the admin.
    /// @custom:requirement The function will revert if called before the timelock expires or if there is no pending update.
    function executeUpdates() external onlyAdmin {
        require(pendingUpdate.pending, "No pending update to execute");
        require(block.timestamp >= pendingUpdate.unlockTime, "Update is still locked");

        for (uint256 i = 1; i <= maxLevel; i++) {
            delete levelThresholds[i];
            delete levelMultipliers[i];
        }
        
        for (uint256 i = 0; i < pendingUpdate.levels.length; i++) {
            levelThresholds[pendingUpdate.levels[i]] = pendingUpdate.thresholds[i];
            levelMultipliers[pendingUpdate.levels[i]] = pendingUpdate.multipliers[i];
        }

        maxLevel = pendingUpdate.levels[pendingUpdate.levels.length - 1];

        delete pendingUpdate;
        emit UpdateExecuted();
    }

    /// @notice Retrieves the multiplier and rank based on the amount staked by the user.
    /// @param user The address of the user whose multiplier and rank are to be calculated.
    /// @return multiplier The multiplier value corresponding to the user's staked amount.
    /// @return rank The rank or level that corresponds to the user's staked amount.
    /// @dev This function calculates the multiplier by checking the user's staked amount against
    ///      predefined levels and thresholds. It only considers the staked amount if the user is
    ///      actively staking and not in the process of unstaking.
    function getMultiplier(address user) external view returns (uint256 multiplier, uint256 rank) {
        (uint256 amountStaked, , , uint256 unstakeInitTime, uint256 stakeInitTime) = stakingContract.stakers(user);

        uint256 balance = 0;
        if (unstakeInitTime == 0 && stakeInitTime > 0) {
            balance = amountStaked;
        }

        if (balance == 0) return (0, 0);

        uint256 lastMultiplier = 0;
        for (uint256 i = 1; i <= maxLevel; i++) {
            if (levelThresholds[i] == 0) continue;
            if (balance < levelThresholds[i]) {
                return (lastMultiplier, i - 1);
            }
            lastMultiplier = levelMultipliers[i];
        }

        return (lastMultiplier, maxLevel);
    }

    /// @notice Proposes an update to the staking contract address with a timelock.
    /// @param _newStakingContract The new staking contract address to be set after the timelock period.
    function proposeStakingContractUpdate(address _newStakingContract) external onlyAdmin {
        require(proposedStakingContract == address(0), "There is already a pending staking contract update");
        proposedStakingContract = _newStakingContract;
        stakingContractUpdateUnlockTime = block.timestamp + UPDATE_INTERVAL;
        emit StakingContractUpdateProposed(_newStakingContract, stakingContractUpdateUnlockTime);
    }

    /// @notice Executes the staking contract update after the timelock period has passed.
    function executeStakingContractUpdate() external onlyAdmin {
        require(block.timestamp >= stakingContractUpdateUnlockTime, "Staking contract update is still locked");
        require(proposedStakingContract != address(0), "No staking contract update proposed");
        stakingContract = IStakingContract(proposedStakingContract);
        proposedStakingContract = address(0); // Reset the proposed address
        emit StakingContractUpdated(address(stakingContract));
    }

    /// @notice Cancels the pending staking contract update.
    function cancelStakingContractUpdate() external onlyAdmin {
        require(proposedStakingContract != address(0), "No staking contract update to cancel");
        emit StakingContractUpdateCancelled(proposedStakingContract);
        proposedStakingContract = address(0); // Reset the proposed address
    }
}

