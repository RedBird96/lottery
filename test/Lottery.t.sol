// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Lottery.sol";
import "../src/FeeRecipient.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    FeeRecipient public feeRecipient;

    // Actors
    address user1 = address(1);
    address user2 = address(2);
    address marketing1 = address(3);
    address marketing2 = address(4);
    address marketing3 = address(5);
    address marketing4 = address(6);

    event LotteryCreated(uint256 lotteryId, uint256 price, uint256 maxNumOfTickets);
    event TicketsBought(address player, uint256 numOfTicket);

    function setUp() public {
        feeRecipient = new FeeRecipient(payable(marketing1), payable(marketing2), payable(marketing3), payable(marketing4));
        lottery = new Lottery(address(feeRecipient));
    }

    function testInitialState() public {
        // assert if manager is set
        assertEq(lottery.manager(), 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
        // assert if manager is admin
        assertEq(lottery.isAdmin(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84), true);
        // assert if the correct FEE was set
        assertEq(lottery.FEE(), 20);
        // assert if the correct feeRecipient was set
        assertEq(lottery.feeRecipient(), address(feeRecipient));
    }

    //  =====   Functionality tests   ===== //

    function testAuthotizedStart(bytes32 randomHash, uint256 price, uint256 maxTickets) public {
        vm.assume(randomHash != 0);
        vm.assume(price > 0);
        vm.assume(maxTickets > 0);
        vm.expectEmit(false, false, false, true);
        // The event we expect
        emit LotteryCreated(1, price, maxTickets);
        // The event we get
        lottery.startLottery(randomHash, price, maxTickets);

        assertEq(lottery.getLotteryInfo(1).price, price);
        assertEq(lottery.getLotteryInfo(1).numOfTickets, 0);
        assertEq(lottery.getLotteryInfo(1).maxNumOfTickets, maxTickets);
        assertEq(lottery.getLotteryInfo(1).randomHash, randomHash);
    }

    function testFailUnauthotizedStart() public {
        vm.prank(user1);
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1, 10);
    }

    function testBuyTicket(uint256 amount) public {
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1, 10);
        vm.deal(user1, 1 ether);

        vm.assume(amount > 0 && amount < 11);
        vm.prank(user1);
        vm.expectEmit(false, false, false, true);
        // The event we expect
        emit TicketsBought(user1, amount);
        // The event we get

        lottery.buyTicket{value: amount * 1}(amount);
        assertEq(lottery.getLotteryInfo(1).numOfTickets, amount);
        assertEq(lottery.getPlayerAtIndex(0), user1);
    }

    function testFailBuyTooManyTickets() public {
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1, 10);
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        lottery.buyTicket{value: 11 * 1}(11);
    }

    function testFailTooManyPlayers() public {
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1, 100);
        for(uint i = 0; i < 101; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: 1 * 1}(1);
        }
    }

    function testFailBuyTicketsWithoutMoney() public {
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1, 10);
        vm.prank(user1);
        lottery.buyTicket{value: 1 * 1}(1);
    }

    function testFailBuyTicketsFromContract() public {
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1, 10);
        vm.deal(address(feeRecipient), 1 ether);
        vm.prank(address(feeRecipient));
        lottery.buyTicket{value: 1 * 1}(1);
    }

    function testPickWinner() public {
        lottery.startLottery(keccak256(abi.encodePacked("ciao")), 1 ether, 10);
        for(uint i = 0; i < 10; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: 1 ether}(1);
        }
        assertEq(lottery.getLotteryInfo(1).numOfTickets, 10);
        uint256 marketing1Before = marketing1.balance;
        uint256 marketing2Before = marketing2.balance;
        uint256 marketing3Before = marketing3.balance;
        uint256 marketing4Before = marketing4.balance;

        lottery.pickWinner("ciao");

        uint256 marketing1After = marketing1.balance;
        uint256 marketing2After = marketing2.balance;
        uint256 marketing3After = marketing3.balance;
        uint256 marketing4After = marketing4.balance;
        uint256 feeAmount = 2 ether * 25 / 100;
        assertEq(lottery.totalPayout(), 8 ether);
        assertEq(lottery.lotteryId(), 2);
        assertEq(marketing1After, marketing1Before + feeAmount);
        assertEq(marketing2After, marketing2Before + feeAmount);
        assertEq(marketing3After, marketing3Before + feeAmount);
        assertEq(marketing4After, marketing4Before + feeAmount);
        assertEq(lottery.getPlayers().length, 0);
        assertEq(lottery.getLotteryWinnerById(1).balance, 8 ether);   
    }

    function testCannotPickWinnerWithWrongSeed() public {
        lottery.startLottery(keccak256(abi.encodePacked("pippo")), 1 ether, 10);
        for(uint i = 0; i < 10; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: 1 ether}(1);
        }
        
        vm.expectRevert(bytes("Seed is not correct"));
        lottery.pickWinner("ciao");
    }

    function testCannotPickWinnerWithNoPlayers() public {
        lottery.startLottery(keccak256(abi.encodePacked("pippo")), 1 ether, 10);
        vm.expectRevert(bytes("No winner to pick"));
        lottery.pickWinner("ciao");
    }

}
