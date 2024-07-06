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
    address user2 = address(5);

    uint256 constant DECIMAL = 10 ** 18;
    uint256 user0DepositAmount = 300 * DECIMAL;
    uint256 user1DepositAmount = 200 * DECIMAL;
    uint256 user2DepositAmount = 500 * DECIMAL;

    function setUp() public {
        //address[] memory users = new address[](2);
        //users[0] = user0;
        //users[1] = user1;

        fyUSD = new MockERC20();
        usdb = new MockERC20();
        idoToken = new MockERC20();

        idoPool = new USDIDOPool();
        idoPool.init(
            address(usdb),
            address(fyUSD),
            address(idoToken),
            treasury,
            block.timestamp,
            block.timestamp + 10 days,
            1000 ether,
            0.05 ether,
            block.timestamp + 10 days
        );

        fyUSD.mint(user0, 1000 * DECIMAL);
        fyUSD.mint(user1, 1000 * DECIMAL);
        usdb.mint(user1, 1000 * DECIMAL);
        usdb.mint(user2, 1000 * DECIMAL);
    }

    function testStateVarialbes() public view {
        address buyToken = idoPool.buyToken();
        address fyToken = idoPool.fyToken();
        address _treasury = idoPool.treasury();
        address _idoToken = idoPool.idoToken();
        uint256 _claimableTime = idoPool.claimableTime();
        uint256 currentTime = block.timestamp;
        uint256 idoPrice = idoPool.idoPrice();
        uint256 decimals = idoPool.idoDecimals();
        uint256 minimumFundingGoal = idoPool.minimumFundingGoal();
        uint256 startTime = idoPool.idoStartTime();
        uint256 endTime = idoPool.idoEndTime();
        uint256 initialClaimTime = idoPool.initialClaimableTime();
        uint256 initialEndTime = idoPool.initialIdoEndTime();

        assertEq(buyToken, address(usdb));
        assertEq(fyToken, address(fyUSD));
        assertEq(_treasury, address(treasury));
        assertEq(_idoToken, address(idoToken));
        assertTrue(_claimableTime - currentTime == 864000);
        assertEq(idoPrice, 0.05 ether);
        assertEq(decimals, 18);
        assertEq(minimumFundingGoal, 1000 ether);
        assertEq(startTime, 1);
        assertEq(endTime, 864001);
        assertEq(initialClaimTime, 864001);
        assertEq(initialEndTime, 864001);
    }

    function test_InvalidParticipateToken() public {
        vm.prank(user0);
        fyUSD.approve(address(idoPool), 100 ether);
        vm.expectRevert(abi.encodeWithSignature("InvalidParticipateToken(address)", address(0)));
        idoPool.participate(address(user0), address(0), 100 ether);
    }

    function testUserCanParticipate() public {
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 300 * DECIMAL);
        idoPool.participate(user0, address(fyUSD), 300 * DECIMAL);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 200 * DECIMAL);
        idoPool.participate(user1, address(usdb), 200 * DECIMAL);
        vm.stopPrank();
    }

    function testStateUpdatesOnParticipate() public {
        uint256 startingBalance0 = fyUSD.balanceOf(user0);
        uint256 startingBalance1 = usdb.balanceOf(user1);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        idoPool.participate(user0, address(fyUSD), user0DepositAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), user1DepositAmount);
        idoPool.participate(user1, address(usdb), user1DepositAmount);
        vm.stopPrank();
        // CHECKS TOTAL FUNDED INSIDE CONTRACT
        uint256 totalFundedFY = idoPool.totalFunded(address(fyUSD));
        uint256 totalFundedUSDB = idoPool.totalFunded(address(usdb));
        assertEq(totalFundedFY, user0DepositAmount);
        assertEq(totalFundedUSDB, user1DepositAmount);
        // CHECKS POSITION OF USERS PARTICIPATION
        (uint256 fyAmount0, uint256 amount0) = idoPool.accountPosition(user0);
        assertEq(fyAmount0, user0DepositAmount);
        assertEq(amount0, user0DepositAmount);

        (uint256 fyAmount1, uint256 amount1) = idoPool.accountPosition(user1);
        assertEq(fyAmount1, 0);
        assertEq(amount1, user1DepositAmount);
        // MAKE SURE TOKENS WERE DEDUCTED FROM USER
        uint256 endingBalance0 = fyUSD.balanceOf(user0);
        uint256 endingBalance1 = usdb.balanceOf(user1);
        assert(startingBalance0 - user0DepositAmount == endingBalance0);
        assert(startingBalance1 - user1DepositAmount == endingBalance1);
    }

    function test_Cannot_Claim_Before_Finalized() public {
        idoToken.mint(address(idoPool), DECIMAL * 1000);

        // USERS APPROVE AND PARTICIPATE

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        idoPool.participate(user0, address(fyUSD), user0DepositAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), user1DepositAmount);
        idoPool.participate(user1, address(usdb), user1DepositAmount);
        vm.stopPrank();

        vm.startPrank(user0);
        vm.expectRevert(abi.encodeWithSignature("NotFinalized()"));
        idoPool.claim(user0);
        vm.stopPrank();
    }

    function test_Cannot_Finalize() public {
        idoToken.mint(address(idoPool), DECIMAL * 1000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        idoPool.participate(user0, address(fyUSD), user0DepositAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), user1DepositAmount);
        idoPool.participate(user1, address(usdb), user1DepositAmount);
        vm.stopPrank();

        // idoEndTime not met
        vm.expectRevert(abi.encodeWithSignature("IDONotEnded()"));
        idoPool.finalize();

        // Forward Time to Ido Endtime
        vm.warp(block.timestamp + 10 days);
        // But reverts due to minimumFundingGoal
        vm.expectRevert(abi.encodeWithSignature("FudingGoalNotReached()"));
        idoPool.finalize();
    }

    function mintApproveParticipateAndFinalize() internal {
        idoToken.mint(address(idoPool), DECIMAL * 1000);

        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        idoPool.participate(user0, address(fyUSD), user0DepositAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), user1DepositAmount);
        idoPool.participate(user1, address(usdb), user1DepositAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(idoPool), user2DepositAmount);
        idoPool.participate(user2, address(usdb), user2DepositAmount);
        vm.stopPrank();

        // Forward Time to Ido Endtime
        vm.warp(block.timestamp + 10 days);

        // FINALIZE success
        idoPool.finalize();
    }

    function test_Can_Finalize() public {
        mintApproveParticipateAndFinalize();
    }

    function test_Check_Variables_After_Finalizing() public {
        mintApproveParticipateAndFinalize();

        // CHECK STATE VARIABLES
        //- snapshots
        uint256 snapshotTokenPrice = idoPool.snapshotTokenPrice();
        uint256 snapshotPriceDecimals = idoPool.snapshotPriceDecimals();
        assertEq(snapshotTokenPrice, snapshotPriceDecimals);

        // - fundedUSDValue
        uint256 fundedUSDValue = idoPool.fundedUSDValue();
        assert(fundedUSDValue == user0DepositAmount + user1DepositAmount + user2DepositAmount);
        assertTrue(idoPool.isFinalized());
    }

    function testCannotParticipateAfterFinalized() public {
        mintApproveParticipateAndFinalize();

        // REVERTS DUE TO FINALIZATION
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        vm.expectRevert(abi.encodeWithSignature("AlreadyFinalized()"));
        idoPool.participate(user0, address(fyUSD), user0DepositAmount);
        vm.stopPrank();
    }

    function test_Users_Can_Claim() public {
        mintApproveParticipateAndFinalize();

        uint256 startingIDOBalance = idoToken.balanceOf(user0);

        vm.startPrank(user0);
        idoPool.claim(address(user0));
        vm.stopPrank();

        uint256 endingIDOBalance = idoToken.balanceOf(user0);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance, startingIDOBalance);
    }

    // TODO 
    function test_Users_Can_Claim_With_Refund() public {
        /*   vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 500 ether);
        idoPool.participate(user0, address(fyUSD),  500 ether);
        vm.stopPrank(); 
 */
        mintApproveParticipateAndFinalize();

        uint256 startingIDOBalance = idoToken.balanceOf(address(idoPool));
        console.log("Starting Balance:", startingIDOBalance);
        vm.startPrank(user0);
        console.log("FY Balance Before Claim:", fyUSD.balanceOf(user0));
        idoPool.claim(address(user0));
        console.log("FY Balance After Claim:", fyUSD.balanceOf(user0));

        vm.stopPrank();

        uint256 balanceAfterClaim0 = idoToken.balanceOf(address(idoPool));
        console.log("balanceAfterClaim0:", balanceAfterClaim0);

        vm.startPrank(user1);
        idoPool.claim(address(user1));
        vm.stopPrank();

        uint256 balanceAfterClaim1 = idoToken.balanceOf(address(idoPool));
        console.log("balanceAfterClaim1:", balanceAfterClaim1);

        vm.startPrank(user2);
        idoPool.claim(address(user2));
        vm.stopPrank();

        uint256 balanceAfterClaim2 = idoToken.balanceOf(address(idoPool));
        console.log("balanceAfterClaim2:", balanceAfterClaim2);
    }

    /*  function testWithdrawSpareNotAffectTokenClaim() public {
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
    } */
}
