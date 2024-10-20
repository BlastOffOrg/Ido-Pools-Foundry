// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MultiplierContract.sol";
import "../src/StandardIDOPool.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy MultiplierContract
        address stakingContractAddress = address(vm.envAddress("TOKEN_STAKING_CA")); // Replace with actual address
        MultiplierContract multiplierContract = new MultiplierContract(stakingContractAddress);

        // Deploy StandardIDOPool implementation
        StandardIDOPool implementation = new StandardIDOPool();

        // Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            StandardIDOPool.init.selector,
            msg.sender,
            address(multiplierContract)
        );

        // Deploy TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        // The address of your deployed and initialized StandardIDOPool is the proxy address
        StandardIDOPool(payable(address(proxy)));

        vm.stopBroadcast();

        console.log("MultiplierContract deployed at:", address(multiplierContract));
        console.log("StandardIDOPool implementation deployed at:", address(implementation));
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        console.log("StandardIDOPool proxy deployed at:", address(proxy));
    }
}
