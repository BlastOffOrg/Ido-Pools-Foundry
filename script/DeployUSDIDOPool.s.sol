// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../src/mock/Proxy.sol";
import {USDIDOPool} from "../src/USDIDOPool.sol";
import {MockERC20} from "../src/mock/MockERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract DeployUSDIDOPool is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy MockERC20 tokens
        MockERC20 usdb = new MockERC20();
        MockERC20 fyUSD = new MockERC20();
        MockERC20 idoToken = new MockERC20();

        // Mint some tokens to the deployer's address for testing
        usdb.mint(msg.sender, 1000000 ether);
        fyUSD.mint(msg.sender, 1000000 ether);
        idoToken.mint(msg.sender, 1000000 ether);

        // Define treasury address (can be deployer's address for testing)
        address treasury = msg.sender;
        uint256 idoStartTime = block.timestamp;
        uint256 idoEndTime = block.timestamp + 2 weeks;
        uint256 minimumFundingGoal = 1000 ether;
        uint256 idoPrice = 1 ether;
        uint256 claimableTime = block.timestamp + 3 weeks;

        // Deploy USDIDOPool logic contract
        USDIDOPool logic = new USDIDOPool();

        // Deploy Proxy contract pointing to the logic contract
        Proxy proxy = new Proxy(address(logic));

        // Initialize the proxy contract with the desired parameters
        USDIDOPool(address(proxy)).init(
            address(usdb),
            address(fyUSD),
            address(idoToken),
            treasury,
            idoStartTime,
            idoEndTime,
            minimumFundingGoal,
            idoPrice,
            claimableTime
        );

        vm.stopBroadcast();

        console.log("Proxy deployed to:", address(proxy));
        console.log("Logic contract deployed to:", address(logic));
        console.log("USDB Token deployed to:", address(usdb));
        console.log("fyUSD Token deployed to:", address(fyUSD));
        console.log("IDO Token deployed to:", address(idoToken));
    }
}

