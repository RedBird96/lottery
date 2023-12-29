// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.13;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {VRFCoordinatorV2Interface} from "lib/chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFv2Consumer} from "./VRFv2Consumer.sol";
import {console} from "lib/forge-std/src/Script.sol";

contract Lottery is 
    Initializable , 
    UUPSUpgradeable, 
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable 
{

    mapping(uint256 => LotteryInfo) public lotteryInfo;
    mapping(uint256 => WinLotteryInfo) public lotteryWinInfo;
    
    mapping(address => bool) public isAdmin;


    address[] public players;

    address public feeRecipient;
    address public manager;
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

    modifier isManager() {
        require(msg.sender == manager);
        _;
    }

    event LotteryCreated(uint256 lotteryId, uint256 price);
    event TicketsBought(address player, uint256 numOfTicket);
    event WinnerPicked(uint256 lotteryId, address indexed winner, uint256 payout);
    event UpdateLotteryPeriod(uint256 oldPeriod, uint256 newPeriod);
    event UpdateTicketPrice(uint256 oldPrice, uint256 newPrice);
    event UpdateFeePercentage(uint256 oldPercentage, uint256 newPercentage);
    event CreateSubId(uint64 id);

    function __Lottery_init(
        address _feeRecipient,
        address _cordinator  
    ) public initializer {
        isAdmin[msg.sender] = true;
        manager = msg.sender;
        feeRecipient = _feeRecipient;
        lotteryId = 1;
        ticketPrice = 1000000000000000000;
        feePercentage = 2000;
        COORDINATOR = _cordinator;
        lotteryPeriod = 24 hours;
        test = 120;
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function sendBNB(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /// @notice Create a new lottery at the first
    function startLottery() external {
        require(isAdmin[msg.sender], "You are not authorized to start a lottery");
        require(lotteryInfo[lotteryId].numOfTickets == 0, "Lottery already started");
        require(ticketPrice > 0, "Ticket Price is not setted");
        require(feeRecipient != address(0), "Fee recipient must be setted");
        lotteryInfo[lotteryId] = LotteryInfo(ticketPrice, 0, block.timestamp, LotteryStatus.OPENED);
        emit LotteryCreated(lotteryId, ticketPrice);
    }

    /// @notice Payout and start a new lottery
    function startNewLottery() external {
        require(isAdmin[msg.sender], "You are not authorized to start a lottery");
        require(ticketPrice > 0, "Ticket Price is not setted");
        require(feeRecipient != address(0), "Fee recipient must be setted");
        if (lotteryInfo[lotteryId].numOfTickets != 0) {
            pickWinner();
        }
        lotteryInfo[lotteryId] = LotteryInfo(ticketPrice, 0, block.timestamp, LotteryStatus.OPENED);
        emit LotteryCreated(lotteryId, ticketPrice);
    }


    /// @notice Buy tickets for the current lottery
    /// @param ticketsNumber The number of tickets to buy
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
        emit TicketsBought(msg.sender, ticketsNumber);
    }

    function createSubscriptionID() external isManager returns(uint64 subId) {
        subId = VRFCoordinatorV2Interface(COORDINATOR).createSubscription();
        subscriptionId = subId;
        emit CreateSubId(subId);
    }

    function addConsumer() external isManager {
        VRFCoordinatorV2Interface(COORDINATOR).addConsumer(subscriptionId, consumer);
    }

    /// @notice Pick a winner for the current lottery
    function pickWinner() public {
        require(isAdmin[msg.sender] == true, "You are not admin");
        require(
            lotteryInfo[lotteryId].status == LotteryStatus.OPENED && 
            lotteryInfo[lotteryId].startTime + lotteryPeriod < block.timestamp
            , "Lottery is not closed");
        require(lotteryInfo[lotteryId].numOfTickets > 0, "No winner to pick");
        require(lotteryInfo[lotteryId].price * lotteryInfo[lotteryId].numOfTickets <= address(this).balance, "Missing funds");
        uint256 winnerIndex = randomNumGenerator() % players.length;
        uint256 payout = lotteryInfo[lotteryId].price * lotteryInfo[lotteryId].numOfTickets;
        uint256 feeAmount = payout * feePercentage / 10000;
        totalPayout += (payout - feeAmount);
        lotteryWinInfo[lotteryId] = WinLotteryInfo(totalPayout, winnerIndex, block.timestamp, players[winnerIndex]);
        sendBNB(payable(players[winnerIndex]), payout - feeAmount);
        sendBNB(payable(feeRecipient), feeAmount);
        lotteryInfo[lotteryId].status = LotteryStatus.CLOSED;
        emit WinnerPicked(lotteryId, players[winnerIndex], payout - feeAmount);
        players = new address[](0);
        lotteryId++;
    }


    function randomNumGenerator() public returns (uint256) {
        require(consumer != address(0), "consumer is not setted");
        return VRFv2Consumer(consumer).requestRandomWords();
    }

    // This functions returns the random number given to us by chainlink
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

    function setManager(address _manager) external isManager {
        manager = _manager;
    }

    function setLotteryPeriod(uint256 newtime) external isManager {
        emit UpdateLotteryPeriod(lotteryPeriod, newtime);
        lotteryPeriod = newtime;
    }

    function setAdmin(address _admin, bool _isAdmin) external isManager {
        isAdmin[_admin] = _isAdmin;
    }

    function setTickeyPrice(uint256 _price) external isManager {
        emit UpdateTicketPrice(ticketPrice, _price);
        ticketPrice = _price;
    }

    function setFeePercentage(uint256 _newPercentage) external isManager {
        emit UpdateFeePercentage(feePercentage, _newPercentage);
        feePercentage = _newPercentage;
    }

    function setVRFConsumer(address _consumer) external isManager {
        consumer = _consumer;
    }

    function getPlayers() external view returns(address[] memory){
        return players;
    }

    function getWinLotteryList() external view returns(WinLotteryInfo[] memory) {
        WinLotteryInfo[] memory result = new WinLotteryInfo[](lotteryId);
        for (uint8 i = 0; i < lotteryId; i ++) {
            result[i] = lotteryWinInfo[i];
        }

        return result;
    }

    function getPlayerAtIndex(uint256 index) external view returns(address){
        return players[index];
    }

    function getLotteryInfo(uint256 _lotteryId) external view returns (LotteryInfo memory) {
        return lotteryInfo[_lotteryId];
    }

    function getLotteryWinnerById(uint256 _lotteryId) public view returns (WinLotteryInfo memory) {
        return lotteryWinInfo[_lotteryId];
    }

}
