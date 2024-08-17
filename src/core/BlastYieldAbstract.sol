// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

interface IBlast {
    function configureClaimableYield() external;
    function configureClaimableGas() external;
    function claimMaxGas(address contractAddress, address recipient) external returns (uint256);
    function claimAllGas(address contractAddress, address recipient) external returns (uint256);
    function claimYield(address contractAddress, address recipient) external returns (uint256);
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
    error ETHTransferFailed();
    error InvalidToken(address token);
    error InsufficientWETHYield();
    error InsufficientUSDBYield();

    function __BlastYieldAbstract_init() internal initializer {
        __Ownable2Step_init();
        WETH.configure(YieldMode.CLAIMABLE);
        USDB.configure(YieldMode.CLAIMABLE);
        BLAST.configureClaimableGas();
        BLAST.configureClaimableYield();

    }

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
            uint256 claimed = BLAST.claimYield(smartContract, smartContract);
            accumulatedETHYield += claimed;
            emit ETHYieldClaimed(claimed);
        }
    }

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
        IERC20Rebasing(token).claim(recipient, amount);
    }

    function claimGas() public onlyOwner {
        address smartContract = address(this);
        uint256 claimed = BLAST.claimAllGas(smartContract, smartContract);
        accumulatedETHYield += claimed;
        emit GasClaimed(claimed);
    }

    function claimMaxGas() public onlyOwner {
        address smartContract = address(this);
        uint256 claimed = BLAST.claimMaxGas(smartContract, smartContract);
        accumulatedETHYield += claimed;
        emit GasClaimed(claimed);
    }

    function withdrawETHYield(address payable recipient, uint256 amount) public onlyOwner {
        if (amount > accumulatedETHYield) {
            revert InsufficientETHYield(amount, accumulatedETHYield);
        }
        accumulatedETHYield -= amount;
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert ETHTransferFailed();
        }
    }

    receive() external payable {}
}



