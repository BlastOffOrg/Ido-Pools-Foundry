// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StandardIDOPoolBaseTest.t.sol";

contract StandardIDOPoolBasicTest is StandardIDOPoolBaseTest {

    // BASIC CALL, not needed apparently
    //function setUp() public override {
    //  super.setUp();
    //}

    // OVERRIDE TEMPLATE

    //function setUp() public override {
    //    super.setUp(); // Call the base contract's setup

        // Replace the buyToken with a different MockERC20 instance
    //    buyToken = new MockERC20("New Buy Token", "NBUY");

        // If the new `buyToken` impacts other parts of the setup, modify them here
        // For example, if you need to reinitialize something with the new buyToken, do it here
    //}

    function testInitialSetup() view public {
        assertEq(address(idoPool.multiplierContract()), address(multiplierContract));
        assertEq(idoPool.treasury(), treasury);
        assertEq(idoPool.owner(), admin);
    }

    function testCreateIDORound() public {
        vm.prank(admin);

        idoPool.createIDORound(
            "Test IDO",
            address(idoToken),
            address(buyToken),
            address(fyToken),
            1 ether, // idoPrice
            1000 ether, // idoSize
            500 ether, // minimumFundingGoal
            5000, // fyTokenMaxBasisPoints (50%)
            uint64(block.timestamp + 1 days), // idoStartTime
            uint64(block.timestamp + 8 days), // idoEndTime
            uint64(block.timestamp + 15 days) // claimableTime
        );
        vm.stopPrank();

        uint32 idoRoundId = idoPool.nextIdoRoundId() - 1;
        (address configIdoToken, , , address configBuyToken, address configFyToken, uint256 configIdoPrice, uint256 configIdoSize, , , uint256 configMinimumFundingGoal, ) = idoPool.idoRoundConfigs(idoRoundId);

        assertEq(configIdoToken, address(idoToken));
        assertEq(configBuyToken, address(buyToken));
        assertEq(configFyToken, address(fyToken));
        assertEq(configIdoPrice, 1 ether);
        assertEq(configIdoSize, 1000 ether);
        assertEq(configMinimumFundingGoal, 500 ether);
    }

    // Add more test functions as needed

}
