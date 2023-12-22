// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";
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

        fee = address(0x2ef73f60F33b167dC018C6B1DCC957F4e4c7e936);
    }

    function deployTest() external {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        cordinator = address(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625);
        _deployerPrivateKey = vm.envUint("TEST_DEPLOYER_KEY");
        _deployLottery();
    }

    function upgradeTest() external {
        string memory rpc = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpc);
        cordinator = address(0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625);
        _deployerPrivateKey = vm.envUint("TEST_DEPLOYER_KEY");
        _upgradeLottery();
    }

    function deployMain() external {
        string memory rpc = vm.envString("ETHERUM_RPC_URL");
        vm.createSelectFork(rpc);
        _deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        _deployLottery();
    }
    function _deployLottery() private broadcast(_deployerPrivateKey) {
        
        address implementation = address(new Lottery());

        bytes memory data = abi.encodeCall(
            Lottery.__Lottery_init, 
            (
                address(fee), 
                address(cordinator)
            )
        );
        address proxy = address(new ERC1967Proxy(implementation, data));

        lottery = Lottery(proxy);

        uint64 subId = lottery.createSubscriptionID();

        consumer = new VRFv2Consumer(subId, cordinator, address(lottery));

        lottery.setVRFConsumer(address(consumer));
        lottery.addConsumer();
        
    }

    function _upgradeLottery() private broadcast(_deployerPrivateKey) {
        address proxyAddress = 0xa11133a37378dfB3d6286c20b654D372b6E4d8D2;
        address implementation = address(new Lottery());
        bytes memory data = abi.encodeCall(
            Lottery.__Lottery_init, 
            (
                address(fee),
                address(cordinator)
            )
        );
        UUPSUpgradeable proxy = UUPSUpgradeable(proxyAddress);
        proxy.upgradeToAndCall(implementation, data);
    }
}
