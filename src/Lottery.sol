// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.13;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {VRFCoordinatorV2Interface} from "lib/chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFv2Consumer} from "./VRFv2Consumer.sol";
import {console} from "lib/forge-std/src/Script.sol";

contract Lottery is 
    Pausable, 
    ReentrancyGuard, 
    Ownable
{

    mapping(uint256 => LotteryInfo) public lotteryInfo;
    mapping(uint256 => WinLotteryInfo) public lotteryWinInfo;
    
    mapping(address => bool) public isAdmin;
    mapping(address => mapping(uint256 => uint256)) public playerAmount;

    address[] public players;

    address public feeRecipient;
    uint256 public lotteryId;
    uint256 public totalPayout;
    uint256 public lotteryPeriod;
    uint256 public ticketPrice;
    uint256 public feePercentage;
    address public consumer;
    address public COORDINATOR;
    uint64 public subscriptionId;
    uint256 public test;

    enum LotteryStatus {
        OPENED,
        CLOSED
    }

    struct LotteryInfo {
        uint256 price;
        uint256 numOfTickets;
        uint256 startTime;
        LotteryStatus status;
    }

    struct WinLotteryInfo {
        uint256 amount;
        uint256 ticketNum;
        uint256 timestamp;
        address player;
    }

    event LotteryCreated(uint256 lotteryId, uint256 price);
    event TicketsBought(address player, uint256 numOfTicket);
    event WinnerPicked(uint256 lotteryId, address indexed winner, uint256 payout);
    event UpdateLotteryPeriod(uint256 oldPeriod, uint256 newPeriod);
    event UpdateTicketPrice(uint256 oldPrice, uint256 newPrice);
    event UpdateFeePercentage(uint256 oldPercentage, uint256 newPercentage);
    event CreateSubId(uint64 id);

    constructor(
        address _feeRecipient, 
        address _cordinator
    ) Ownable(msg.sender) {
        isAdmin[msg.sender] = true;
        feeRecipient = _feeRecipient;
        lotteryId = 1;
        ticketPrice = 1000000000000000;
        feePercentage = 2000;
        COORDINATOR = _cordinator;
        lotteryPeriod = 5 minutes;
        test = 120;
    }

    // Pause the contract to prevent certain functionalities
    function pause() public onlyOwner {
        _pause();
    }

    // Unpause the contract to re-enable functionalities
    function unpause() public onlyOwner {
        _unpause();
    }

    function sendBNB(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @notice start new lottery without pick winner
     */
    function startLottery() external whenNotPaused {
        require(isAdmin[msg.sender], "You are not authorized to start a lottery");
        require(lotteryInfo[lotteryId].numOfTickets == 0, "Lottery already started");
        require(ticketPrice > 0, "Ticket Price is not setted");
        require(feeRecipient != address(0), "Fee recipient must be setted");
        lotteryInfo[lotteryId] = LotteryInfo(ticketPrice, 0, block.timestamp, LotteryStatus.OPENED);
        emit LotteryCreated(lotteryId, ticketPrice);
    }

    /**
     * @notice start new lottery after pick winner
     */
    function startNewLottery() external whenNotPaused {
        require(isAdmin[msg.sender], "You are not authorized to start a lottery");
        require(ticketPrice > 0, "Ticket Price is not setted");
        require(feeRecipient != address(0), "Fee recipient must be setted");
        if (lotteryInfo[lotteryId].numOfTickets != 0) {
            pickWinner();
        }
        lotteryInfo[lotteryId] = LotteryInfo(ticketPrice, 0, block.timestamp, LotteryStatus.OPENED);
        emit LotteryCreated(lotteryId, ticketPrice);
    }


    /**
     * @notice Buy tickets for the current lottery
     * @param ticketsNumber the number of tickets to buy
     */
    function buyTicket(uint256 ticketsNumber) external payable {
        require(
            lotteryInfo[lotteryId].startTime + lotteryPeriod > block.timestamp && 
            lotteryInfo[lotteryId].status == LotteryStatus.OPENED
            ,"Lottery is closed");
        require(msg.sender.code.length == 0, "Address must be a EOA");
        require(ticketsNumber > 0, "Number of tickets must be greater than 0");
        require(msg.value == lotteryInfo[lotteryId].price * ticketsNumber, "Ticket price not met");
        lotteryInfo[lotteryId].numOfTickets += ticketsNumber;
        for(uint256 i; i < ticketsNumber; ){
            players.push(msg.sender);
            unchecked{
                ++i;
            }
        }
        playerAmount[msg.sender][lotteryId] += msg.value;
        emit TicketsBought(msg.sender, ticketsNumber);
    }

    /**
     * @notice create subscription ID for making consumer object
     */
    function createSubscriptionID() external onlyOwner returns(uint64 subId) {
        subId = VRFCoordinatorV2Interface(COORDINATOR).createSubscription();
        subscriptionId = subId;
        emit CreateSubId(subId);
    }

    /**
     * @notice add consumer contract
     */
    function addConsumer() external onlyOwner {
        VRFCoordinatorV2Interface(COORDINATOR).addConsumer(subscriptionId, consumer);
    }

    /**
     * @notice pick winner for current lottery
     */
    function pickWinner() public {
        require(isAdmin[msg.sender] == true, "You are not admin");
        require(
            lotteryInfo[lotteryId].status == LotteryStatus.OPENED && 
            lotteryInfo[lotteryId].startTime + lotteryPeriod < block.timestamp
            , "Lottery is not closed");
        //require(lotteryInfo[lotteryId].numOfTickets > 0, "No winner to pick");
        require(lotteryInfo[lotteryId].price * lotteryInfo[lotteryId].numOfTickets <= address(this).balance, "Missing funds");
        uint256 winnerIndex = randomNumGenerator() % players.length;
        uint256 payout = lotteryInfo[lotteryId].price * lotteryInfo[lotteryId].numOfTickets;
        uint256 feeAmount = payout * feePercentage / 10000;
        uint256 sendAmount = payout - feeAmount;
        totalPayout += sendAmount;
        lotteryWinInfo[lotteryId] = WinLotteryInfo(sendAmount, winnerIndex + 1, block.timestamp, players[winnerIndex]);
        sendBNB(payable(players[winnerIndex]), sendAmount);
        sendBNB(payable(feeRecipient), feeAmount);
        lotteryInfo[lotteryId].status = LotteryStatus.CLOSED;
        emit WinnerPicked(lotteryId, players[winnerIndex], sendAmount);
        players = new address[](0);
        lotteryId++;
    }

    /**
     * @notice generator random number
     */
    function randomNumGenerator() public returns (uint256) {
        require(consumer != address(0), "consumer is not setted");
        return VRFv2Consumer(consumer).requestRandomWords();
    }

    /**
     * @notice genetrator random string
     */
    function randomWordGenerator() public view returns (uint256) {
        //    uint256 requestID = getRequestId();
        uint256 requestID = VRFv2Consumer(consumer).lastRequestId();
        // Get random words array
        (, uint256[] memory randomWords) = VRFv2Consumer(consumer).getRequestStatus(
            requestID
        );

        // return first random word
        return randomWords[0];
    }

    /**
     * @notice set lottery period
     */
    function setLotteryPeriod(uint256 newtime) external onlyOwner {
        emit UpdateLotteryPeriod(lotteryPeriod, newtime);
        lotteryPeriod = newtime;
    }

    /**
     * @notice set admin permission
     */
    function setAdmin(address _admin, bool _isAdmin) external onlyOwner {
        isAdmin[_admin] = _isAdmin;
    }

    /**
     * @notice set ticket price
     */
    function setTicketPrice(uint256 _price) external onlyOwner {
        emit UpdateTicketPrice(ticketPrice, _price);
        ticketPrice = _price;
    }

    /**
     * @notice set fee percentage for the lottery
     */
    function setFeePercentage(uint256 _newPercentage) external onlyOwner {
        emit UpdateFeePercentage(feePercentage, _newPercentage);
        feePercentage = _newPercentage;
    }

    /**
     * @notice set vrf consumer for get chainlink random
     */
    function setVRFConsumer(address _consumer) external onlyOwner {
        consumer = _consumer;
    }

    /**
     * @notice withdraw assets to receive
     * @param _receiver the receiver address
     */
    function withdraw(address _receiver) external onlyOwner {
        uint256 amount = address(this).balance;
        sendBNB(payable(_receiver), amount);
    }

    /**
     * @notice return players info
     */
    function getPlayers() external view returns(address[] memory){
        return players;
    }

    /**
     * @notice return past lottery info
     */
    function getWinLotteryList() external view returns(WinLotteryInfo[] memory) {
        WinLotteryInfo[] memory result = new WinLotteryInfo[](lotteryId);
        for (uint8 i = 0; i < lotteryId; i ++) {
            result[i] = lotteryWinInfo[i];
        }

        return result;
    }

    /**
     * @notice get player by index
     */
    function getPlayerAtIndex(uint256 index) external view returns(address){
        return players[index];
    }

    /**
     * @notice get lottery by index
     */
    function getLotteryInfo(uint256 _lotteryId) external view returns (LotteryInfo memory) {
        return lotteryInfo[_lotteryId];
    }

    /**
     * @notice get past lottery by index
     */
    function getLotteryWinnerById(uint256 _lotteryId) public view returns (WinLotteryInfo memory) {
        return lotteryWinInfo[_lotteryId];
    }

    /**
     * @notice get player history by address
     */
    function getPlayerHistory(address _address) 
        public 
        view 
        returns (uint256[] memory amount, uint256[] memory result) 
    {
        uint8 index = 0;
        amount = new uint256[](lotteryId);
        result = new uint256[](lotteryId);

        for(index = 0; index < lotteryId; index ++) {
            amount[index] = playerAmount[_address][index];
            if (lotteryWinInfo[index].player == _address) {
                result[index] = 1;
            } else {
                result[index] = 0;
            }
        }

        return (amount, result);
    }

    receive() external payable {
    }
}
