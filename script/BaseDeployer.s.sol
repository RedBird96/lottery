// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "lib/forge-std/src/Script.sol";

/* solhint-disable max-states-count */
contract BaseDeployer is Script {
    uint256 internal _deployerPrivateKey;

    enum Chains {
        Sepolia,
        Etherum,
        Arbitrum,
        LocalSepolia    
    }

    enum Cycle {
        Dev,
        Test,
        Prod
    }

    /// @dev Mapping of chain enum to rpc url
    mapping(Chains => string) public forks;

    /// @dev environment variable setup for deployment
    /// @param cycle deployment cycle (dev, test, prod)
    modifier setEnvDeploy(Cycle cycle) {
        if (cycle == Cycle.Dev) {
            _deployerPrivateKey = vm.envUint("LOCAL_DEPLOYER_KEY");
        } else if (cycle == Cycle.Test) {
            _deployerPrivateKey = vm.envUint("TEST_DEPLOYER_KEY");
        } else {
            _deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
        }

        _;
    }

    /// @dev broadcast transaction modifier
    /// @param pk private key to broadcast transaction
    modifier broadcast(uint256 pk) {
        vm.startBroadcast(pk);

        _;

        vm.stopBroadcast();
    }

    constructor() {
        // Local
        forks[Chains.LocalSepolia] = vm.envString("LOCAL_GOERLI_RPC_URL");

        // Testnet
        forks[Chains.Sepolia] = vm.envString("SEPOLIA_RPC_URL");

        // Mainnet
        forks[Chains.Etherum] = vm.envString("ETHERUM_RPC_URL");
        forks[Chains.Arbitrum] = vm.envString("ARBITRUM_RPC_URL");
    }

    function createFork(Chains chain) public {
        vm.createFork(forks[chain]);
    }

    function createSelectFork(Chains chain) public {
        vm.createSelectFork(forks[chain]);
    }
}