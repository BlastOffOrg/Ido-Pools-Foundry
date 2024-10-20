// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBlast {
    function configureClaimableYield() external;
    function configureClaimableGas() external;
    function claimMaxGas(address contractAddress, address recipient) external returns (uint256);
    function claimAllGas(address contractAddress, address recipient) external returns (uint256);
    function claimAllYield(address contractAddress, address recipient) external returns (uint256);
    function readClaimableYield(address contractAddress) external view returns (uint256);
}

interface IERC20Rebasing {
    function configure(YieldMode) external returns (uint256);
    function claim(address recipient, uint256 amount) external returns (uint256);
    function getClaimableAmount(address account) external view returns (uint256);
}

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}

contract BlastYieldAbstract is Ownable2StepUpgradeable {
    IBlast private constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
    IERC20Rebasing private constant USDB = IERC20Rebasing(0x4300000000000000000000000000000000000003);
    IERC20Rebasing private constant WETH = IERC20Rebasing(0x4300000000000000000000000000000000000004);

    // NOTE: the commented lines below are the testnet addresses
    // IERC20Rebasing private constant USDB = IERC20Rebasing(0x4200000000000000000000000000000000000022);
    // IERC20Rebasing private constant WETH = IERC20Rebasing(0x4200000000000000000000000000000000000023);

    uint256 public accumulatedWETHYield;
    uint256 public accumulatedUSDBYield;
    uint256 public accumulatedETHYield;

    event YieldClaimed(address token, uint256 amount);
    event GasClaimed(uint256 amount);
    event ETHYieldClaimed(uint256 amount);

    error InsufficientETHYield(uint256 requested, uint256 available);
    error InvalidToken(address token);
    error InsufficientWETHYield();
    error InsufficientUSDBYield();
    error TransferFailed();

    function __BlastYieldAbstract_init() internal onlyInitializing {
        __Ownable2Step_init();
        WETH.configure(YieldMode.CLAIMABLE);
        USDB.configure(YieldMode.CLAIMABLE);
        BLAST.configureClaimableGas();
    }

    function setupYield() external onlyOwner {
        BLAST.configureClaimableYield();
    }
    /**
        * @notice Claims all available yield for WETH, USDB, and ETH
        * @dev This function can only be called by the contract owner
        * @dev Claims WETH and USDB yield using the IERC20Rebasing interface
        * @dev Claims ETH yield using the IBlast interface
        * @dev Updates the accumulated yield amounts for each token type
        * @dev Emits YieldClaimed events for WETH and USDB, and ETHYieldClaimed for ETH
        */
    function claimYield() public onlyOwner {
        address smartContract = address(this);

        uint256 wethClaimableAmount = WETH.getClaimableAmount(smartContract);
        if (wethClaimableAmount > 0) {
            WETH.claim(smartContract, wethClaimableAmount);
            accumulatedWETHYield += wethClaimableAmount;
            emit YieldClaimed(address(WETH), wethClaimableAmount);
        }

        uint256 usdbClaimableAmount = USDB.getClaimableAmount(smartContract);
        if (usdbClaimableAmount > 0) {
            USDB.claim(smartContract, usdbClaimableAmount);
            accumulatedUSDBYield += usdbClaimableAmount;
            emit YieldClaimed(address(USDB), usdbClaimableAmount);
        }

        uint256 ethClaimableAmount = BLAST.readClaimableYield(smartContract);
        if (ethClaimableAmount > 0) {
            uint256 claimed = BLAST.claimAllYield(smartContract, smartContract);
            accumulatedETHYield += claimed;
            emit ETHYieldClaimed(claimed);
        }
    }

    /**
        * @notice Withdraws accumulated yield for WETH or USDB
        * @dev This function can only be called by the contract owner
        * @param token The address of the token to withdraw (must be WETH or USDB)
        * @param recipient The address to receive the withdrawn yield
        * @param amount The amount of yield to withdraw
        * @custom:throws InvalidToken if the token is not WETH or USDB
        * @custom:throws InsufficientWETHYield if trying to withdraw more WETH than accumulated
        * @custom:throws InsufficientUSDBYield if trying to withdraw more USDB than accumulated
        * @custom:throws TransferFailed if the token transfer fails
        */
    function withdrawAccumulatedYield(address token, address recipient, uint256 amount) public onlyOwner {
        if (token != address(WETH) && token != address(USDB)) {
            revert InvalidToken(token);
        }

        if (token == address(WETH)) {
            if (amount > accumulatedWETHYield) {
                revert InsufficientWETHYield();
            }
            accumulatedWETHYield -= amount;
        } else {
            if (amount > accumulatedUSDBYield) {
                revert InsufficientUSDBYield();
            }
            accumulatedUSDBYield -= amount;
        }        

        bool success = IERC20(token).transfer(recipient, amount);
        if (!success) {
            revert TransferFailed();
        }

    }

    /**
        * @notice Claims all available gas yield
        * @dev This function can only be called by the contract owner
        * @dev Uses the IBlast interface to claim all gas
        * @dev Adds the claimed amount to the accumulated ETH yield
        * @dev Emits a GasClaimed event with the claimed amount
        */
    function claimGas() public onlyOwner {
        address smartContract = address(this);
        uint256 claimed = BLAST.claimAllGas(smartContract, smartContract);
        accumulatedETHYield += claimed;
        emit GasClaimed(claimed);
    }

    /**
        * @notice Claims the maximum available gas yield
        * @dev This function can only be called by the contract owner
        * @dev Uses the IBlast interface to claim the maximum gas
        * @dev Adds the claimed amount to the accumulated ETH yield
        * @dev Emits a GasClaimed event with the claimed amount
        */
    function claimMaxGas() public onlyOwner {
        address smartContract = address(this);
        uint256 claimed = BLAST.claimMaxGas(smartContract, smartContract);
        accumulatedETHYield += claimed;
        emit GasClaimed(claimed);
    }

    /**
        * @notice Withdraws accumulated ETH yield
        * @dev This function can only be called by the contract owner
        * @param recipient The address to receive the withdrawn ETH yield
        * @param amount The amount of ETH yield to withdraw
        * @custom:throws InsufficientETHYield if trying to withdraw more ETH than accumulated
        * @custom:throws TransferFailed if the ETH transfer fails
        */
    function withdrawETHYield(address payable recipient, uint256 amount) public onlyOwner {
        if (amount > accumulatedETHYield) {
            revert InsufficientETHYield(amount, accumulatedETHYield);
        }
        accumulatedETHYield -= amount;
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    receive() external payable {}
}



