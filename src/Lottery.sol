// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.13;

import {VRFCoordinatorV2Interface} from "lib/chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFv2Consumer} from "./VRFv2Consumer.sol";
import {console} from "lib/forge-std/src/Script.sol";

contract Lottery {

    mapping(uint256 => address) lotteryWinner;
    mapping(uint256 => LotteryInfo) lotteryInfo;
    
    mapping(address => bool) public isAdmin;


    address[] players;

    address public feeRecipient;
    address public manager;
    uint256 public lotteryId;
    uint256 public totalPayout;
    uint256 public lotteryPeriod = 24 hours;
    uint256 public ticketPrice;
    uint256 public feePercentage;
    address public consumer;
    address public COORDINATOR;
    uint64 public subscriptionId;

    struct LotteryInfo {
        uint256 price;
        uint256 numOfTickets;
        uint256 maxNumOfTickets;
        bytes32 randomHash;
        uint256 startTime;
    }

    modifier isManager() {
        require(msg.sender == manager);
        _;
    }

    event LotteryCreated(uint256 lotteryId, uint256 price, uint256 maxNumOfTickets);
    event TicketsBought(address player, uint256 numOfTicket);
    event WinnerPicked(uint256 lotteryId, address indexed winner, uint256 payout);
    event UpdateLotteryPeriod(uint256 oldPeriod, uint256 newPeriod);
    event UpdateTicketPrice(uint256 oldPrice, uint256 newPrice);
    event UpdateFeePercentage(uint256 oldPercentage, uint256 newPercentage);
    event CreateSubId(uint64 id);

    constructor(address _feeRecipient, address _cordinator) {
        isAdmin[msg.sender] = true;
        manager = msg.sender;
        feeRecipient = _feeRecipient;
        lotteryId = 1;
        ticketPrice = 1000000000000000000;
        feePercentage = 2000;
        COORDINATOR = _cordinator;
    }

    function sendBNB(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /// @notice Create a new lottery
    /// @param randomHash The hash of a random string (you can use https://emn178.github.io/online-tools/keccak_256.html )
    /// @param maxNumOfTickets The maximum number of tickets that can be bought
    function startLottery(bytes32 randomHash, uint256 maxNumOfTickets) external {
        require(isAdmin[msg.sender], "You are not authorized to start a lottery");
        require(lotteryInfo[lotteryId].numOfTickets == 0, "Lottery already started");
        require(maxNumOfTickets > 0, "Max number of tickets must be greater than 0");
        require(ticketPrice > 0, "Ticket Price is not setted");
        require(feeRecipient != address(0), "Fee recipient must be setted");
        require(randomHash != 0, "Winner hash must be set");
        lotteryInfo[lotteryId] = LotteryInfo(ticketPrice, 0, maxNumOfTickets, randomHash, block.timestamp);
        emit LotteryCreated(lotteryId, ticketPrice, maxNumOfTickets);
    }

    /// @notice Buy tickets for the current lottery
    /// @param ticketsNumber The number of tickets to buy
    function buyTicket(uint256 ticketsNumber) external payable {
        require(lotteryInfo[lotteryId].startTime + lotteryPeriod > block.timestamp, "Lottery is closed");
        require(msg.sender.code.length == 0, "Address must be a EOA");
        require(lotteryInfo[lotteryId].maxNumOfTickets > 0, "Lottery not started");
        require(ticketsNumber > 0, "Number of tickets must be greater than 0");
        require(msg.value == lotteryInfo[lotteryId].price * ticketsNumber, "Ticket price not met");
        require(lotteryInfo[lotteryId].maxNumOfTickets >= lotteryInfo[lotteryId].numOfTickets + ticketsNumber, "Too many tickets");
        lotteryInfo[lotteryId].numOfTickets += ticketsNumber;
        for(uint256 i; i < ticketsNumber; ){
            players.push(msg.sender);
            unchecked{
                ++i;
            }
        }
        emit TicketsBought(msg.sender, ticketsNumber);
    }

    /// @notice Pick a winner for the current lottery
    /// @param seed The random string used to compute the hash at the start
    /// @dev VRF is is not necessary since the extraction is handled by the staff
    function pickWinner(string calldata seed) external{
        require(isAdmin[msg.sender] == true, "You are not admin");
        require(lotteryInfo[lotteryId].numOfTickets > 0, "No winner to pick");
        require(lotteryInfo[lotteryId].randomHash ==  keccak256(abi.encodePacked(seed)), "Seed is not correct");
        require(lotteryInfo[lotteryId].price * lotteryInfo[lotteryId].numOfTickets <= address(this).balance, "Missing funds");
        uint256 winnerIndex = randomNumGenerator() % players.length;
        uint256 payout = lotteryInfo[lotteryId].price * lotteryInfo[lotteryId].numOfTickets;
        uint256 feeAmount = payout * feePercentage / 10000;
        lotteryWinner[lotteryId] = players[winnerIndex];
        totalPayout += (payout - feeAmount);
        players = new address[](0);
        sendBNB(payable(lotteryWinner[lotteryId]), payout - feeAmount);
        sendBNB(payable(feeRecipient), feeAmount);
        emit WinnerPicked(lotteryId, lotteryWinner[lotteryId], payout - feeAmount);
        lotteryId++;
    }

    function createSubscriptionID() external isManager returns(uint64 subId) {
        subId = VRFCoordinatorV2Interface(COORDINATOR).createSubscription();
        subscriptionId = subId;
        emit CreateSubId(subId);
    }

    function addConsumer() external isManager {
        VRFCoordinatorV2Interface(COORDINATOR).addConsumer(subscriptionId, consumer);
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

    function random(string calldata seed) internal view returns(uint256){
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, seed)));
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

    function getPlayerAtIndex(uint256 index) external view returns(address){
        return players[index];
    }

    function getLotteryInfo(uint256 _lotteryId) external view returns (LotteryInfo memory) {
        return lotteryInfo[_lotteryId];
    }

    function getLotteryWinnerById(uint256 _lotteryId) public view returns (address) {
        return lotteryWinner[_lotteryId];
    }
}
