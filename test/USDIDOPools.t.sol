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
    uint256 user0MintAmount = 1000 * DECIMAL;
    uint256 user1MintAmount = 1000 * DECIMAL;
    uint256 user2MintAmount = 1000 * DECIMAL;
    uint256 user0DepositAmount = 200 * DECIMAL;
    uint256 user1DepositAmount = 400 * DECIMAL;
    uint256 user2DepositAmount = 400 * DECIMAL;
    uint256 minimumFundingGoal = 1000000000000000000000;
    uint256 idoPrice = 1000000000000000000;

    function setUp() public {
        fyUSD = new MockERC20();
        usdb = new MockERC20();
        idoToken = new MockERC20();

        idoPool = new USDIDOPool();

        fyUSD.mint(user0, user0MintAmount);
        usdb.mint(user1, user1MintAmount);
        usdb.mint(user2, user2MintAmount);
        idoToken.mint(address(idoPool), ((minimumFundingGoal / idoPrice)) * DECIMAL);

        idoPool.init(
            address(usdb),
            address(fyUSD),
            address(idoToken),
            treasury,
            block.timestamp,
            block.timestamp + 10 days,
            minimumFundingGoal,
            idoPrice,
            block.timestamp + 10 days
        );
    }

    function testStateVarialbes() public view {
        address buyToken = idoPool.buyToken();
        address fyToken = idoPool.fyToken();
        address _treasury = idoPool.treasury();
        address _idoToken = idoPool.idoToken();
        uint256 _claimableTime = idoPool.claimableTime();
        uint256 currentTime = block.timestamp;
        uint256 _idoPrice = idoPool.idoPrice();
        uint256 decimals = idoPool.idoDecimals();
        uint256 _minimumFundingGoal = idoPool.minimumFundingGoal();
        uint256 startTime = idoPool.idoStartTime();
        uint256 endTime = idoPool.idoEndTime();
        uint256 initialClaimTime = idoPool.initialClaimableTime();
        uint256 initialEndTime = idoPool.initialIdoEndTime();

        assertEq(buyToken, address(usdb));
        assertEq(fyToken, address(fyUSD));
        assertEq(_treasury, address(treasury));
        assertEq(_idoToken, address(idoToken));
        assertTrue(_claimableTime - currentTime == 864000);
        assertEq(_idoPrice, idoPrice);
        assertEq(decimals, 18);
        assertEq(_minimumFundingGoal, minimumFundingGoal);
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
        fyUSD.approve(address(idoPool), 300 ether);
        idoPool.participate(user0, address(fyUSD), 300 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), 400 ether);
        idoPool.participate(user1, address(usdb), 400 ether);
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

    function approveParticipateAndFinalize() internal {
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
        approveParticipateAndFinalize();
    }

    function test_Check_Variables_After_Finalizing() public {
        approveParticipateAndFinalize();

        // CHECK STATE VARIABLES
        //- snapshots
        uint256 snapshotTokenPrice = idoPool.snapshotTokenPrice();
        uint256 snapshotPriceDecimals = idoPool.snapshotPriceDecimals();
        // console.log("snapshotTokenPrice", snapshotTokenPrice);
        // console.log("snapshotPriceDecimals", snapshotPriceDecimals);
        assertEq(snapshotTokenPrice, 1);
        assertEq(snapshotPriceDecimals, 1);

        // - fundedUSDValue
        uint256 fundedUSDValue = idoPool.fundedUSDValue();
        assert(fundedUSDValue == (user0DepositAmount + user1DepositAmount + user2DepositAmount));
        assertTrue(idoPool.isFinalized());
    }

    function testCannotParticipateAfterFinalized() public {
        approveParticipateAndFinalize();

        // REVERTS DUE TO FINALIZATION
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        vm.expectRevert(abi.encodeWithSignature("AlreadyFinalized()"));
        idoPool.participate(user0, address(fyUSD), user0DepositAmount);
        vm.stopPrank();
    }

    function test_Users_Can_Claim() public {
        approveParticipateAndFinalize();

        uint256 fundedUSDValue = idoPool.fundedUSDValue();
        console.log("fundedUSDValue", fundedUSDValue);

        uint256 idoSize = idoPool.idoSize();
        console.log("idoSize", idoSize);

        //Contract IDO token balance
        uint256 contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract: ", contractBalance);

        (, uint256 amount0) = idoPool.accountPosition(user0);
        (, uint256 amount1) = idoPool.accountPosition(user1);
        (, uint256 amount2) = idoPool.accountPosition(user2);

        /* uint snapshotTokenPrice = idoPool.snapshotTokenPrice();
        console.log("snapshotTokenPrice",snapshotTokenPrice); */

        // USER 0 CLAIM
        uint256 startingIDOBalance0 = idoToken.balanceOf(user0);
        console.log("starting IDOBalance User0", startingIDOBalance0);
        vm.startPrank(user0);
        idoPool.claim(address(user0));
        vm.stopPrank();
        uint256 endingIDOBalance0 = idoToken.balanceOf(user0);
        console.log("ending IDOBalance User0", endingIDOBalance0);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance0, startingIDOBalance0);
        //Contract IDO token balance
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after user 0 claims: ", contractBalance);

        // USER 1 CLAIM
        uint256 startingIDOBalance1 = idoToken.balanceOf(user1);
        console.log("starting IDOBalance User1", startingIDOBalance1);
        vm.startPrank(user1);
        idoPool.claim(address(user1));
        vm.stopPrank();
        uint256 endingIDOBalance1 = idoToken.balanceOf(user1);
        console.log("ending IDOBalance User1", endingIDOBalance1);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance1, startingIDOBalance1);
        //Contract IDO token balance
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after user 1 claims: ", contractBalance);

        // USER 2 CLAIM
        uint256 startingIDOBalance2 = idoToken.balanceOf(user2);
        console.log("starting IDOBalance User2", startingIDOBalance2);
        vm.startPrank(user2);
        idoPool.claim(address(user2));
        vm.stopPrank();
        uint256 endingIDOBalance2 = idoToken.balanceOf(user2);
        console.log("ending IDOBalance User2", endingIDOBalance2);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance2, startingIDOBalance2);
        //Contract IDO token balance
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after user 2 claims: ", contractBalance);

        // Checks that user was not refunded
        uint256 fyusdBalanceUser0 = fyUSD.balanceOf(user0);
        uint256 usdbBalanceUser1 = usdb.balanceOf(user1);
        uint256 usdbBalanceUser2 = usdb.balanceOf(user2);
        assertEq(amount0, user0MintAmount - fyusdBalanceUser0);
        assertEq(amount1, user1MintAmount - usdbBalanceUser1);
        assertEq(amount2, user2MintAmount - usdbBalanceUser2);
    }

    function test_Users_Can_Claim_With_Refund() public {
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), 200 ether);
        idoPool.participate(user0, address(fyUSD), 200 ether);
        vm.stopPrank();

        approveParticipateAndFinalize();

        uint256 fundedUSDValue = idoPool.fundedUSDValue();
        console.log("fundedUSDValue", fundedUSDValue);

        uint256 idoSize = idoPool.idoSize();
        console.log("idoSize", idoSize);

        //Contract IDO token balance
        uint256 contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract: ", contractBalance);

        //( ,uint256 amount0) = idoPool.accountPosition(user0);
        //( ,uint256 amount1) = idoPool.accountPosition(user1);
        //( ,uint256 amount2) = idoPool.accountPosition(user2);

        /* uint snapshotTokenPrice = idoPool.snapshotTokenPrice();
        console.log("snapshotTokenPrice",snapshotTokenPrice); */

        // USER 0 CLAIM
        uint256 startingIDOBalance0 = idoToken.balanceOf(user0);
        console.log("starting IDOBalance User0", startingIDOBalance0);
        vm.startPrank(user0);
        idoPool.claim(address(user0));
        vm.stopPrank();
        uint256 endingIDOBalance0 = idoToken.balanceOf(user0);
        console.log("ending IDOBalance User0", endingIDOBalance0);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance0, startingIDOBalance0);
        //Contract IDO token balance
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after user 0 claims: ", contractBalance);

        // USER 1 CLAIM
        uint256 startingIDOBalance1 = idoToken.balanceOf(user1);
        console.log("starting IDOBalance User1", startingIDOBalance1);
        vm.startPrank(user1);
        idoPool.claim(address(user1));
        vm.stopPrank();
        uint256 endingIDOBalance1 = idoToken.balanceOf(user1);
        console.log("ending IDOBalance User1", endingIDOBalance1);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance1, startingIDOBalance1);
        //Contract IDO token balance
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after user 1 claims: ", contractBalance);

        // USER 2 CLAIM
        uint256 startingIDOBalance2 = idoToken.balanceOf(user2);
        console.log("starting IDOBalance User2", startingIDOBalance2);
        vm.startPrank(user2);
        idoPool.claim(address(user2));
        vm.stopPrank();
        uint256 endingIDOBalance2 = idoToken.balanceOf(user2);
        console.log("ending IDOBalance User2", endingIDOBalance2);
        // USER RECEIVES IDO TOKEN
        assertGt(endingIDOBalance2, startingIDOBalance2);
        //Contract IDO token balance
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after user 2 claims: ", contractBalance);

        // Checks that user was not refunded
        uint256 fyusdBalanceUser0 = fyUSD.balanceOf(user0);
        uint256 usdbBalanceUser1 = usdb.balanceOf(user1);
        uint256 usdbBalanceUser2 = usdb.balanceOf(user2);
        console.log(fyusdBalanceUser0);
        console.log(usdbBalanceUser1);
        console.log(usdbBalanceUser2);

        //assertEq(amount0,1000 * DECIMAL- fyusdBalanceUser0);
        //assertEq(amount1,1000 * DECIMAL- usdbBalanceUser1);
        //assertEq(amount2,1000 * DECIMAL- usdbBalanceUser2);
    }

    function testWithdrawSpareNotAffectTokenClaim() public {
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        idoPool.participate(user0, address(fyUSD), 100 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), user1DepositAmount);
        idoPool.participate(user1, address(usdb), 100 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(idoPool), user2DepositAmount);
        idoPool.participate(user2, address(usdb), 100 ether);
        vm.stopPrank();

        // Forward Time to Ido Endtime
        vm.warp(block.timestamp + 10 days);

        //Contract IDO token balance
        uint256 contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract: ", contractBalance);

        idoPool.withdrawSpareIDO();
        contractBalance = idoToken.balanceOf(address(idoPool));
        console.log("IDO token balance in contract after Withdraw: ", contractBalance);
    }

    function test_Attempt_To_Claim_After_Withdrawing_Failed_IDO() public {
        vm.startPrank(user0);
        fyUSD.approve(address(idoPool), user0DepositAmount);
        idoPool.participate(user0, address(fyUSD), 100 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        usdb.approve(address(idoPool), user1DepositAmount);
        idoPool.participate(user1, address(usdb), 100 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        usdb.approve(address(idoPool), user2DepositAmount);
        idoPool.participate(user2, address(usdb), 100 ether);
        vm.stopPrank();

        // Forward Time to Ido Endtime
        vm.warp(block.timestamp + 10 days);

        //Contract IDO token balance
      

        idoPool.withdrawSpareIDO();


        
        vm.startPrank(user1);
        idoPool.refund(user1);
        vm.stopPrank(); 

        // Check users USDB balance post refund
        uint256 userBalance = usdb.balanceOf(user1);
        assert(userBalance == user1MintAmount);
    }
}
