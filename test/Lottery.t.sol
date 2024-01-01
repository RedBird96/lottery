// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console} from "lib/forge-std/src/Script.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Lottery} from "../src/Lottery.sol";
import {VRFv2Consumer} from "../src/VRFv2Consumer.sol";

contract LotteryTest is Test {
    Lottery public lottery;
    VRFv2Consumer public consumer;

    // Actors
    address public manager = address(0x2ef73f60F33b167dC018C6B1DCC957F4e4c7e936);
    address public user1 = address(1);
    address public user2 = address(2);
    address public feeReceiver = address(3);

    event LotteryCreated(uint256 lotteryId, uint256 maxNumOfTickets);
    event TicketsBought(address player, uint256 numOfTicket);

    function setUp() public {
        vm.createSelectFork("https://eth-sepolia.g.alchemy.com/v2/gugiiHEtV3akg3p4Y8y0kYFHT4Fe6nND", 4936679);
        vm.startPrank(manager);

        address implementation = address(new Lottery());

        bytes memory data = abi.encodeCall(
            Lottery.__Lottery_init, 
            (
                address(feeReceiver), 
                address(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625)
            )
        );
        address proxy = address(new ERC1967Proxy(implementation, data));

        lottery = Lottery(payable(proxy));

        // lottery = new Lottery(address(feeReceiver), address(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625));
        uint64 subId = lottery.createSubscriptionID();
        consumer = new VRFv2Consumer(subId, address(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625), address(lottery));
        lottery.setVRFConsumer(address(consumer));
        lottery.addConsumer();
        vm.stopPrank();
    }

    function testInitialState() public {
        // assert if manager is admin
        assertEq(lottery.isAdmin(0x2ef73f60F33b167dC018C6B1DCC957F4e4c7e936), true);
        // assert if the correct FEE was set
        assertEq(lottery.feePercentage(), 2000);
        // // assert if the correct feeRecipient was set
        assertEq(lottery.feeRecipient(), address(feeReceiver));
    }

    //  =====   Functionality tests   ===== //

    function testSetPrice(uint256 price) public {
        vm.prank(manager);
        lottery.setTicketPrice(price);
        assertEq(lottery.ticketPrice(), price);
    }

    function testAuthotizedStart(bytes32 randomHash, uint256 maxTickets) public {
        vm.assume(randomHash != 0);
        vm.assume(maxTickets > 0);
        // vm.expectEmit(1, maxTickets);
        // The event we expect
        emit LotteryCreated(1, maxTickets);
        // The event we get
        vm.prank(manager);
        lottery.startLottery();

        assertEq(lottery.getLotteryInfo(1).numOfTickets, 0);
    }

    function testFailUnauthotizedStart() public {
        vm.prank(user1);
        lottery.startLottery();
    }

    function testBuyTicket(uint256 amount) public {
        vm.prank(manager);
        lottery.startLottery();
        vm.deal(user1, 1 ether);

        vm.assume(amount > 0 && amount < 11);
        // vm.expectEmit(false, false, false, true);
        // The event we expect
        // emit TicketsBought(user1, amount);
        // The event we get

        uint256 price = lottery.ticketPrice();
        vm.deal(user1, amount * 1 ether);
        vm.prank(user1);
        lottery.buyTicket{value: amount * price}(amount);
        assertEq(lottery.getLotteryInfo(1).numOfTickets, amount);
        assertEq(lottery.getPlayerAtIndex(0), user1);
    }

    function testFailBuyTooManyTickets() public {
        lottery.startLottery();
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        lottery.buyTicket{value: 11 * 1}(11);
    }

    function testFailTooManyPlayers() public {
        lottery.startLottery();
        for(uint i = 0; i < 101; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: 1 * 1}(1);
        }
    }

    function testFailBuyTicketsWithoutMoney() public {
        lottery.startLottery();
        vm.prank(user1);
        lottery.buyTicket{value: 1 * 1}(1);
    }

    function testFailBuyTicketsFromContract() public {
        lottery.startLottery();
        vm.deal(address(feeReceiver), 1 ether);
        vm.prank(address(feeReceiver));
        lottery.buyTicket{value: 1 * 1}(1);
    }

    function testPickWinnerBeforeClosed() public {
        vm.prank(manager);
        lottery.startLottery();
        uint256 price = lottery.ticketPrice();
        for(uint i = 0; i < 10; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: price}(1);
        }
        assertEq(lottery.getLotteryInfo(1).numOfTickets, 10);

        vm.prank(manager);
        vm.expectRevert(bytes("Lottery is not closed"));
        lottery.pickWinner();

    }

    function testPickWinner() public {
        vm.prank(manager);
        lottery.startLottery();
        uint256 snapshot = block.timestamp;
        uint256 price = lottery.ticketPrice();
        for(uint i = 0; i < 10; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: price}(1);
        }
        assertEq(lottery.getLotteryInfo(1).numOfTickets, 10);
        uint256 feeReceiverBefore = feeReceiver.balance;

        snapshot = snapshot + lottery.lotteryPeriod() + 1;
        vm.warp(snapshot);
        vm.prank(manager);
        lottery.pickWinner();

        uint256 feeReceiverAfter = feeReceiver.balance;
        uint256 feeAmount = 10 ether * 20 / 100;
        assertEq(lottery.totalPayout(), 8 ether);
        assertEq(lottery.lotteryId(), 2);
        assertEq(feeReceiverAfter, feeReceiverBefore + feeAmount);
        assertEq(lottery.getPlayers().length, 0);
        assertEq(lottery.getLotteryWinnerById(1).amount, 8 ether);   

        address player1 = vm.addr(12);
        vm.deal(player1, 1 ether);
        vm.prank(player1);
        vm.expectRevert(bytes("Lottery is closed"));
        lottery.buyTicket{value: price}(1);

    }

    function testPickWinnerAndStartNew() public {
        vm.prank(manager);
        lottery.startLottery();
        uint256 snapshot = block.timestamp;
        uint256 price = lottery.ticketPrice();
        for(uint i = 0; i < 10; i++) {
            address player = vm.addr(i+1);
            vm.deal(player, 1 ether);
            vm.prank(player);
            lottery.buyTicket{value: price}(1);
        }
        assertEq(lottery.getLotteryInfo(1).numOfTickets, 10);
        uint256 feeReceiverBefore = feeReceiver.balance;

        snapshot = snapshot + lottery.lotteryPeriod() + 1;
        vm.warp(snapshot);
        vm.prank(manager);
        lottery.startNewLottery();

        uint256 feeReceiverAfter = feeReceiver.balance;
        uint256 feeAmount = 10 ether * 20 / 100;
        assertEq(lottery.totalPayout(), 8 ether);
        assertEq(lottery.lotteryId(), 2);
        assertEq(feeReceiverAfter, feeReceiverBefore + feeAmount);
        assertEq(lottery.getPlayers().length, 0);
        assertEq(lottery.getLotteryWinnerById(1).amount, 8 ether);   

        address player1 = vm.addr(12);
        vm.deal(player1, 1 ether);
        vm.prank(player1);
        lottery.buyTicket{value: price}(1);
        assertEq(lottery.getLotteryInfo(2).numOfTickets, 1);
        snapshot = snapshot + lottery.lotteryPeriod() + 1;
        vm.warp(snapshot);
        vm.prank(manager);
        lottery.startNewLottery();
        assertEq(lottery.totalPayout(), 8.8 ether);
        assertEq(lottery.lotteryId(), 3);

        address player2 = vm.addr(13);
        vm.deal(player2, 2 ether);
        vm.prank(player2);
        lottery.buyTicket{value: price}(1);
        assertEq(player2.balance, 1 ether);
        vm.prank(manager);
        lottery.withdraw(player2);
        assertEq(player2.balance, 2 ether);

        lottery.getPlayerHistory(player1);
    }

    function testCannotPickWinnerWithNoPlayers() public {
        vm.prank(manager);
        lottery.startLottery();
        uint256 snapshot = block.timestamp;
        snapshot = snapshot + lottery.lotteryPeriod() + 1;
        vm.warp(snapshot);
        vm.expectRevert(bytes("No winner to pick"));
        vm.prank(manager);
        lottery.pickWinner();
    }

}
