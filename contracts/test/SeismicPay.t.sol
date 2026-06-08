// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SeismicPay.sol";

contract SeismicPayTest is Test {
    SeismicPay pay;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        pay = new SeismicPay();
        vm.deal(alice, 10 ether);
        vm.deal(bob, 1 ether);
    }

    function test_DepositCreditsBalance() public {
        vm.prank(alice);
        pay.deposit{value: 5 ether}();
        vm.prank(alice);
        assertEq(pay.balanceOf(alice), 5 ether);
    }

    function test_TransferMovesShieldedBalance() public {
        vm.prank(alice);
        pay.deposit{value: 5 ether}();
        vm.prank(alice);
        pay.transfer(bob, suint256(2 ether));

        vm.prank(alice);
        assertEq(pay.balanceOf(alice), 3 ether);
        vm.prank(bob);
        assertEq(pay.balanceOf(bob), 2 ether);
    }

    function test_OnlyOwnerCanReadBalance() public {
        vm.prank(alice);
        pay.deposit{value: 1 ether}();
        vm.prank(bob);
        vm.expectRevert("only owner can read");
        pay.balanceOf(alice);
    }
}
