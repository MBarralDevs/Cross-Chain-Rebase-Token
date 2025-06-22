// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 public SEND_VALUE = 1e5;

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardToVault(uint256 amount) public {
        // This function is used to add Ether to the vault for testing purposes
        payable(address(vault)).call{value: amount}("");
    }

    //Fuzz testing that we can deposit Ether into the vault
    function testDeposit(uint256 amount) public {
        //0 - bound the amount to a reasonable range
        amount = bound(amount, 1e3, type(uint96).max);
        //1 - Deposit Ether for the user into the vault
        vm.prank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
    }

    //Fuzz testing that check that when we deposit, the amount of interest grows linearly
    function testDepositIsLinear(uint256 amount) public {
        //0 - bound the amount to a reasonable range
        amount = bound(amount, 1e5, type(uint96).max);
        //1 - Deposit Ether for the user into the vault
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        //2 - check our rebase token balance
        uint256 userBalanceStep1 = rebaseToken.balanceOf(user);
        assertEq(userBalanceStep1, amount);

        //3 - Change the time forward to simulate interest accumulation, then check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 userBalanceStep2 = rebaseToken.balanceOf(user);
        assertGt(userBalanceStep2, userBalanceStep1);

        //4 - Do the exact same thing one more time keeping the same change in time
        vm.warp(block.timestamp + 1 hours);
        uint256 userBalanceStep3 = rebaseToken.balanceOf(user);
        assertGt(userBalanceStep3, userBalanceStep2);

        //5 - Check that the balance has increased by the same amount each time
        assertApproxEqAbs(userBalanceStep2 - userBalanceStep1, userBalanceStep3 - userBalanceStep2, 1);
        vm.stopPrank();
    }

    //Test that we cant redeem more than the balance of the user
    function testCannotRedeemMoreThanBalance() public {
        // Deposit funds
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        vm.expectRevert();
        vault.redeem(SEND_VALUE + 1);
        vm.stopPrank();
    }

    //Fuzz testing that check we can redeem directly after depositing
    function testRedeemAfterDeposit(uint256 amount) public {
        //0 - bound the amount to a reasonable range
        amount = bound(amount, 1e5, type(uint96).max);
        //1 - Deposit Ether for the user into the vault
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //2 - check our rebase token balance
        uint256 userBalance = rebaseToken.balanceOf(user);
        assertEq(userBalance, amount);
        //3 - Redeem the same amount of Ether back to the user
        vault.redeem(amount);
        //4 - Check that the user's balance is now zero
        uint256 userBalanceAfterRedeem = rebaseToken.balanceOf(user);
        assertEq(userBalanceAfterRedeem, 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePasses(uint256 depositAmount, uint256 time) public {
        //0 - bound deposit amount and time
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        //1 - Deposit Ether for the user into the vault
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        //2 - Warp time + check our rebase token balance
        uint256 initialBalance = rebaseToken.balanceOf(user);
        assertEq(initialBalance, depositAmount);

        vm.warp(block.timestamp + time);
        uint256 balanceAfterTime = rebaseToken.balanceOf(user);

        //3 - add the reward to the vault
        vm.deal(owner, balanceAfterTime - initialBalance);
        vm.prank(owner);
        addRewardToVault(balanceAfterTime - initialBalance);

        //4 - Redeem the same amount of Ether + interest back to the user
        vm.prank(user);
        vault.redeem(balanceAfterTime);

        //5 - Check that the redeem went through successfully
        uint256 ethBalanceAfterRedeem = address(user).balance;
        assertEq(ethBalanceAfterRedeem, balanceAfterTime);
        assertGt(ethBalanceAfterRedeem, depositAmount);
    }

    function testTransfer(uint256 amountDeposit, uint256 amountTransfer) public {
        //0 - bound the amounts
        amountDeposit = bound(amountDeposit, 1e5 + 1e3, type(uint96).max);
        amountTransfer = bound(amountTransfer, 1e5, amountDeposit - 1e3);

        //1 - Deposit Ether for the user into the vault
        vm.deal(user, amountDeposit);
        vm.prank(user);
        vault.deposit{value: amountDeposit}();

        //2 - We create a second user to transfer the tokens to
        address user2 = makeAddr("user2");
        uint256 user1BalanceBefore = rebaseToken.balanceOf(user);
        uint256 user2BalanceBefore = rebaseToken.balanceOf(user2);
        assertEq(user1BalanceBefore, amountDeposit);
        assertEq(user2BalanceBefore, 0);

        //3 - We are gonna update the interest to check that the transfer modifies the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10); // Set a new interest rate

        //4 - Transfer the tokens from user to user2
        vm.prank(user);
        rebaseToken.transfer(user2, amountTransfer);

        uint256 user1BalanceAfter = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfter = rebaseToken.balanceOf(user2);
        assertEq(user1BalanceAfter, user1BalanceBefore - amountTransfer);
        assertEq(user2BalanceAfter, user2BalanceBefore + amountTransfer);

        //5 - Check if after some time, the balance of the 2 users has increased
        vm.warp(block.timestamp + 1 days);
        uint256 user1BalanceAfterTime = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTime = rebaseToken.balanceOf(user2);
        assertGt(user1BalanceAfterTime, user1BalanceAfter);
        assertGt(user2BalanceAfterTime, user2BalanceAfter);

        //6 - Check that the interest rate of user2 has been updated to the current interest rate
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(user2);
        uint256 user1InterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(user2InterestRate, user1InterestRate);
    }

    //Fuzz testing that we can set a new interest rate as the owner
    function testSetInterestRate(uint256 newInterestRate) public {
        // bound the interest rate to be less than the current interest rate
        newInterestRate = bound(newInterestRate, 0, rebaseToken.getInterestRate() - 1);
        // Update the interest rate
        vm.startPrank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, newInterestRate);
        vm.stopPrank();

        // check that if someone deposits, this is their new interest rate
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        vm.stopPrank();
        assertEq(userInterestRate, newInterestRate);
    }

    //Fuzz testing that we cant update the interest rate if we are not the owner
    function testCannotSetInterest(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    //Testting that we cant mint if our user doesn't have the mint role
    function testCannotMint() public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.mint(user, SEND_VALUE);
    }

    //Testing that we cannot burn if our user doesn't have the burn role
    function testCannotBurn() public {
        vm.prank(user);
        vm.expectRevert();
        rebaseToken.burn(user, SEND_VALUE);
    }

    //Fuzz testing that we can get the principal balance of a user after depositing
    function testGetPrincipalBalance(uint256 amount) public {
        //0 - bound the amount to a reasonable range
        amount = bound(amount, 1e5, type(uint96).max);

        //1 - Deposit Ether for the user into the vault
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        //2 - check that the principal balance of our user is equal to the amount deposited
        assertEq(rebaseToken.principalBalanceOf(user), amount);

        //3 - check that the principal balance of a user stays the same after some time
        vm.warp(block.timestamp + 1 days);
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }
}
