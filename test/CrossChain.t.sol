// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

contract CrossChainTest is Test {
    //States variables
    uint256 ethSepolia;
    uint256 arbSepolia;

    CCIPLocalSimulatorFork ccipLocalSimulator;

    function setUp() public {
        //1 - Setting up our fork on our source chain (ETH Sepolia)
        ethSepoliaFork = vm.createSelectFork("sepolia-eth");

        //2 - Setting up our fork on our destination chain (Arbitrum Sepolia)
        arbSepoliaFork = vm.createFork("arb-sepolia");

        //3 - Deploying the CCIP Local Simulator contract
        ccipLocalSimulator = new CCIPLocalSimulatorFork();

        // 4. Make the simulator's address persistent across all active forks
        // This is crucial so both the Sepolia and Arbitrum Sepolia forks
        // can interact with the *same* instance of the simulator.
        vm.makePersistent(address(ccipLocalSimulator));
    }
}
