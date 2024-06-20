// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@redstone-finance/evm-connector/contracts/core/CalldataExtractor.sol";
import "../src/USDIDOPool.sol";
import "../src/mock/MockERC20.sol";

contract USDIDOPoolsTest is Test {
    USDIDOPool idoPool;
    MockERC20 fyUSD;
    MockERC20 usdb;
    MockERC20 idoToken;
    address deployer = address(1);
    address treasury = address(2);
    address user0 = address(3);
    address user1 = address(4);

    uint256 constant DECIMAL = 10 ** 18;

    function setUp() public {
        //address[] memory users = new address[](2);
        //users[0] = user0;
        //users[1] = user1;

        fyUSD = new MockERC20();
        usdb = new MockERC20();
        idoToken = new MockERC20();

        idoPool = new USDIDOPool();
        idoPool.init(address(usdb), address(fyUSD), address(idoToken), 18, treasury, 0, 0, 0, DECIMAL, block.timestamp + 10 days);

        fyUSD.mint(user0, 1000 * DECIMAL);
        fyUSD.mint(user1, 1000 * DECIMAL);
        usdb.mint(user1, 1000 * DECIMAL);
    }

    function testUserCanParticipate() public {
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyUSD), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        idoPool.participate(user1, address(usdb), 1000 * DECIMAL);
        vm.stopPrank();
    }

    function testCannotClaimBeforeFinalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyUSD), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        idoPool.participate(user1, address(usdb), 1000 * DECIMAL);
        //vm.expectRevert("NotFinalized()");
        // NOTE: The above doesn't work. Something to do with the proxy ?
        vm.expectRevert(abi.encodeWithSignature("NotFinalized()"));
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.claim(user0);
        vm.stopPrank();
    }

    function testCanFinalize() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyUSD), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        idoPool.participate(user1, address(usdb), 1000 * DECIMAL);
        vm.stopPrank();

        // Mocking the finalize step
        idoPool.finalize();

        vm.startPrank(user0);
        idoPool.claim(user0);
        vm.stopPrank();
        assertEq(idoToken.balanceOf(user0), 1000 * DECIMAL);

        vm.startPrank(user1);
        idoPool.claim(user1);
        vm.stopPrank();
        assertEq(idoToken.balanceOf(user1), 1000 * DECIMAL);
    }

    function testWithdrawSpareNotAffectTokenClaim() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyUSD), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        idoPool.participate(user1, address(usdb), 1000 * DECIMAL - 12);
        vm.stopPrank();

        // Mocking the finalize step

        idoPool.finalize();

        vm.startPrank(user0);
        idoPool.claim(user0);
        vm.stopPrank();
        assertEq(idoToken.balanceOf(user0), 1000 * DECIMAL);

        idoPool.withdrawSpareIDO();

        vm.startPrank(user1);
        idoPool.claim(user1);
        vm.stopPrank();
        assertEq(idoToken.balanceOf(user1), 1000 * DECIMAL - 12);

        uint256 treasuryBal = usdb.balanceOf(treasury) + fyUSD.balanceOf(treasury);
        assertEq(treasuryBal, 2000 * DECIMAL - 12);
    }

    function testCannotParticipateAfterFinalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyUSD), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        idoPool.participate(user1, address(usdb), 1000 * DECIMAL);
        vm.stopPrank();

        // Mocking the finalize step
        idoPool.finalize();

        vm.startPrank(user1);
        //See  testCannotClaimBeforeFinalized comments.
        deal(user1, 1 ether);
        vm.expectRevert(abi.encodeWithSignature("AlreadyFinalized()"));
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);

        vm.stopPrank();
    }

    function testRefundCorrectAmountAfterFinalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 1000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyUSD), 1000 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        idoPool.participate(user1, address(usdb), 1000 * DECIMAL);
        vm.stopPrank();

        address[] memory stakers = new address[](2);
        stakers[0] = user0;
        stakers[1] = user1;

        // Mocking the finalize step
        idoPool.finalize();

        for (uint256 i = 0; i < stakers.length; i++) {
            vm.startPrank(stakers[i]);
            idoPool.claim(stakers[i]);
            vm.stopPrank();
        }

        uint256[] memory balances = new uint256[](2);
        balances[0] = idoToken.balanceOf(user0);
        balances[1] = idoToken.balanceOf(user1);

        assertEq(balances[0], 500 * DECIMAL);
        assertEq(balances[1], 500 * DECIMAL);

        assertEq(fyUSD.balanceOf(user0), (DECIMAL * 1000) / 2);
        assertEq(usdb.balanceOf(user1), (DECIMAL * 1000) / 2);

        uint256 treasuryBal = usdb.balanceOf(treasury) + fyUSD.balanceOf(treasury);
        assertEq(treasuryBal, 1000 * DECIMAL);
    }
}
