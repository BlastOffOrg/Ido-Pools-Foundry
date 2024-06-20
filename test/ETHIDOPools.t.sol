// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@redstone-finance/evm-connector/contracts/core/CalldataExtractor.sol";
import "../src/ETHIDOPool.sol";
import "../src/mock/MockERC20.sol";

contract ETHIDOPoolsTest is Test {
    ETHIDOPool idoPool;
    MockERC20 fyETH;
    MockERC20 idoToken;
    address deployer = address(1);
    address treasury = address(2);
    address user0 = address(3);
    address user1 = address(4);

    uint256 constant DECIMAL = 10 ** 18;

    function setUp() public {
        deployer = address(this);

        fyETH = new MockERC20();
        idoToken = new MockERC20();

        idoPool = new ETHIDOPool();
        idoPool.init(
            address(fyETH),
            address(idoToken),
            //18,
            treasury,
            true,
            0,
            0,
            0,
            DECIMAL,
            block.timestamp + 10 days
        );
    }

    function testUserCanParticipate() public {
        fyETH.mint(user0, DECIMAL);

        vm.startPrank(user0);
        fyETH.approve(address(idoPool), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyETH), DECIMAL);
        vm.stopPrank();

        deal(user1, 10 ether);
        vm.startPrank(user1);
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);
        vm.stopPrank();
    }

    function testCannotClaimBeforeFinalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        fyETH.mint(user0, DECIMAL);

        vm.startPrank(user0);
        fyETH.approve(address(idoPool), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyETH), DECIMAL);
        vm.stopPrank();

        deal(user1, 10 ether);
        vm.startPrank(user1);
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        vm.expectRevert(abi.encodeWithSignature("NotFinalized()"));
        idoPool.claim(user0);
        vm.stopPrank();
    }

    function testCanFinalize() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        fyETH.mint(user0, DECIMAL);

        vm.startPrank(user0);
        fyETH.approve(address(idoPool), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyETH), DECIMAL);
        vm.stopPrank();
        deal(user1, 1 ether);
        vm.startPrank(user1);
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);
        vm.stopPrank();
        // Mocking the finalize step with Redstone WrapperBuilder
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

        fyETH.mint(user0, DECIMAL);

        vm.startPrank(user0);
        fyETH.approve(address(idoPool), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyETH), DECIMAL);
        vm.stopPrank();

        deal(user1, 10 ether);
        vm.startPrank(user1);
        idoPool.participate{value: DECIMAL - 12}(user1, address(0), DECIMAL - 12);
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
        assertEq(idoToken.balanceOf(user1), 1000 * (DECIMAL - 12));

        uint256 treasuryBal = treasury.balance + fyETH.balanceOf(treasury);
        assertEq(treasuryBal, 2 * DECIMAL - 12);
    }

    function testCannotParticipateAfterFinalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 4000);

        fyETH.mint(user0, DECIMAL);

        vm.startPrank(user0);
        fyETH.approve(address(idoPool), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyETH), DECIMAL);
        vm.stopPrank();

        deal(user1, 10 ether);
        vm.startPrank(user1);
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);
        vm.stopPrank();

        // Mocking the finalize step
        idoPool.finalize();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("AlreadyFinalized()"));
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);
        vm.stopPrank();
    }

    function testRefundCorrectAmountAfterFinalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 1000);

        fyETH.mint(user0, DECIMAL);

        vm.startPrank(user0);
        fyETH.approve(address(idoPool), DECIMAL);
        vm.stopPrank();

        vm.startPrank(user0);
        idoPool.participate(user0, address(fyETH), DECIMAL);
        vm.stopPrank();

        deal(user1, 10 ether);
        vm.startPrank(user1);
        idoPool.participate{value: DECIMAL}(user1, address(0), DECIMAL);
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

        assertEq(fyETH.balanceOf(user0), DECIMAL / 2);
        assertEq(user1.balance, DECIMAL / 2);

        uint256 treasuryBal = treasury.balance + fyETH.balanceOf(treasury);
        assertEq(treasuryBal, DECIMAL);
    }
}
