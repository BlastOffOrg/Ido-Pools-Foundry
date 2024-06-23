pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/mock/MockERC20.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployScript is Script {

    function run() external returns (address, address) {
        //we need to declare the sender's private key here to sign the deploy transaction
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 fyUSD = new MockERC20();
       MockERC20 usdb = new MockERC20();
       MockERC20 idoToken = new MockERC20();

     


        // Deploy the upgradeable contract
      /*   address _proxyAddress = Upgrades.deployTransparentProxy(
            "USDIDOPool.sol",
            msg.sender,
            abi.encodeCall(UpgradeableToken.initialize, ())
        );

        // Get the implementation address
        address implementationAddress = Upgrades.getImplementationAddress(
            _proxyAddress
        ); */

        vm.stopBroadcast();

      //  return (implementationAddress, _proxyAddress);
    }
}
