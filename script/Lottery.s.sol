// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {VRFv2Consumer} from "../src/VRFv2Consumer.sol";
import {BaseDeployer} from "./BaseDeployer.s.sol";

contract LotteryScript is Script {

    Lottery public lottery;
    VRFv2Consumer public consumer;
    address public fee;
    uint256 internal _deployerPrivateKey;
    address public cordinator;

    /// @dev broadcast transaction modifier
    /// @param pk private key to broadcast transaction
    modifier broadcast(uint256 pk) {
        vm.startBroadcast(pk);

        _;

        vm.stopBroadcast();
    }

    function setUp() public {

        fee = address(0x59cb61E9c2dF95500c68B91D329f7481F0427D41);
    }

    function deployTest() external {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        cordinator = address(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625);
        _deployerPrivateKey = vm.envUint("TEST_DEPLOYER_KEY");
        _deployLottery();
    }

    function deployMain() external {
        string memory rpc = vm.envString("ETHERUM_RPC_URL");
        vm.createSelectFork(rpc);
        _deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        _deployLottery();
    }
    function _deployLottery() private broadcast(_deployerPrivateKey) {
        
        lottery = new Lottery(fee, cordinator);

        uint64 subId = lottery.createSubscriptionID();

        consumer = new VRFv2Consumer(subId, cordinator, address(lottery));

        lottery.setVRFConsumer(address(consumer));
        lottery.addConsumer();
        
    }
}
