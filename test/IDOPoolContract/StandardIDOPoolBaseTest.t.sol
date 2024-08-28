// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/Test.sol";
import "../../src/StandardIDOPool.sol";
import "../../src/mock/MockERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./mock/MockMultiplierContract.sol"; // Import MockMultiplierContract

contract StandardIDOPoolBaseTest is Test {
    StandardIDOPool public idoPool;
    MockMultiplierContract public multiplierContract;
    MockERC20 public buyToken;
    MockERC20 public fyToken;
    MockERC20 public idoToken;

    address public admin = address(1);
    address public treasury = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public proxyAdmin = address(5);

    function setUp() public virtual {
        vm.startPrank(admin);

        buyToken = new MockERC20("Buy Token", "BUY");
        fyToken = new MockERC20("FY Token", "FY");
        idoToken = new MockERC20("IDO Token", "IDO");

        multiplierContract = new MockMultiplierContract();

        // Deploy StandardIDOPool implementation
        StandardIDOPool implementation = new StandardIDOPool();

        // Mock Blast-related functions
        vm.mockCall(
            address(0x4300000000000000000000000000000000000002), // BLAST contract address
            abi.encodeWithSignature("configureClaimableYield()"),
            abi.encode()
        );

        vm.mockCall(
            address(0x4300000000000000000000000000000000000002), // BLAST contract address
            abi.encodeWithSignature("configureClaimableGas()"),
            abi.encode()
        );

        vm.mockCall(
            address(0x4300000000000000000000000000000000000004), // WETH contract address
            abi.encodeWithSignature("configure(uint8)"),
            abi.encode(0)
        );

        vm.mockCall(
            address(0x4300000000000000000000000000000000000003), // USDB contract address
            abi.encodeWithSignature("configure(uint8)"),
            abi.encode(0)
        );

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            StandardIDOPool.init.selector,
            treasury,
            address(multiplierContract) // Using this contract as a mock multiplier contract
        );

        // Deploy TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            proxyAdmin, // admin is the proxy admin
            initData
        );

        // Cast the proxy address to StandardIDOPool
        idoPool = StandardIDOPool(payable(address(proxy)));

        //vm.prank(admin);
        //idoPool.grantRole(idoPool.DEFAULT_ADMIN_ROLE(), nonAdmin);

        vm.stopPrank();
    }

}

