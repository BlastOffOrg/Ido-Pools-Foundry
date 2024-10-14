// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/mock/MockERC20.sol";

contract Multimint is Script {
    function run() external {
        vm.startBroadcast();

        address[] memory tokenAddresses = new address[](5);
        tokenAddresses[0] = vm.envAddress("MOCK_OFF");
        tokenAddresses[1] = vm.envAddress("MOCK_ETH");
        tokenAddresses[2] = vm.envAddress("MOCK_FYETH");
        tokenAddresses[3] = vm.envAddress("MOCK_USDB");
        tokenAddresses[4] = vm.envAddress("MOCK_FYUSDB");

        address[] memory recipientAddresses = new address[](1);
        recipientAddresses[0] = vm.envAddress("TESTUSER_WALLET_ADDRESS");

        uint256 amount = 1_000_000 * 1e18; // 1000 tokens, assuming 18 decimals

        for (uint i = 0; i < tokenAddresses.length; i++) {
            MockERC20 token = MockERC20(tokenAddresses[i]);
            
            for (uint j = 0; j < recipientAddresses.length; j++) {
                try token.mint(recipientAddresses[j], amount) {
                } catch {
                }
            }
        }

        vm.stopBroadcast();
    }
}
