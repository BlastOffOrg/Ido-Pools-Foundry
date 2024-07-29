// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/USDIDOPoolV2.sol"; // Your new version
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradeScript is Script {
    function run() external {
        vm.startBroadcast();

        // Address of the existing proxy (from your previous deployment)
        address proxyAddress = 0xDB8cFf278adCCF9E9b5da745B44E754fC4EE3C76;
        
        // Address of the existing ProxyAdmin (from your previous deployment)
        address proxyAdminAddress = 0xBb2180ebd78ce97360503434eD37fcf4a1Df61c3;

        // Deploy the new implementation
        USDIDOPoolV2 newImplementation = new USDIDOPoolV2();

        // Get the ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Upgrade the proxy to the new implementation
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(proxyAddress)), address(newImplementation));

        vm.stopBroadcast();

        console.log("New implementation deployed at:", address(newImplementation));
        console.log("Proxy upgraded to new implementation");
    }
}
