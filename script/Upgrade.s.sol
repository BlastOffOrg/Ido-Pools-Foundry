// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/StandardIDOPool.sol"; // Your new version
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradeScript is Script {
    function run() external {
        vm.startBroadcast();

        // Read addresses from environment variables
        // Address of the existing proxy (from your previous deployment)
        address proxyAddress = vm.envAddress("IDO_POOL_PROXY_CA");
        // Address of the existing ProxyAdmin (from your previous deployment)
        address proxyAdminAddress = vm.envAddress("IDO_POOL_PROXY_ADMIN");

        // Deploy the new implementation
        StandardIDOPool newImplementation = new StandardIDOPool();

        // Get the ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // Upgrade the proxy to the new implementation
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(proxyAddress), address(newImplementation));

        vm.stopBroadcast();

        console.log("New implementation deployed at:", address(newImplementation));
        console.log("Proxy upgraded to new implementation");
    }
}
