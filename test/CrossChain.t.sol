// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract CrossChainTest is Test {
    //States variables
    address owner = makeAddr("owner");
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken ethSepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool ethSepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails ethSepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    RegistryModuleOwnerCustom registryModuleOwnerCustomEthSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomArbSepolia;

    TokenAdminRegistry tokenAdminRegistryEthSepolia;
    TokenAdminRegistry tokenAdminRegistryArbSepolia;

    function setUp() public {
        //1 - Setting up our fork on our source chain (ETH Sepolia)
        ethSepoliaFork = vm.createSelectFork("sepolia-eth");

        //a. Setting up our fork on our destination chain (Arbitrum Sepolia)
        arbSepoliaFork = vm.createFork("arb-sepolia");

        //b. Deploying the CCIP Local Simulator contract
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        //c. Make the simulator's address persistent across all active forks
        vm.makePersistent(address(ccipLocalSimulatorFork));

        //d. Deploying the RebaseToken contract on the source chain (eth Sepolia)
        ethSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        ethSepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(ethSepoliaToken)));
        ethSepoliaPool = new RebaseTokenPool(
            IERC20(address(ethSepoliaToken)),
            new address[](0), // No allowlist for simplicity
            ethSepoliaNetworkDetails.rmnProxyAddress,
            ethSepoliaNetworkDetails.routerAddress
        );

        //e. Grant mint and burn role to our source token
        ethSepoliaToken.grantMintAndBurnRole(address(ethSepoliaPool));
        ethSepoliaToken.grantMintAndBurnRole(address(vault));

        //f. Claim role on Sepolia
        registryModuleOwnerCustomEthSepolia =
            RegistryModuleOwnerCustom(ethSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomEthSepolia.registerAdminViaOwner(address(ethSepoliaToken));

        //g. Accept the role on Sepolia
        tokenAdminRegistryEthSepolia = TokenAdminRegistry(ethSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryEthSepolia.acceptAdminRole(address(ethSepoliaToken));

        //h. Link token to pool in the token admin registry on Sepolia
        tokenAdminRegistryEthSepolia.setPool(address(ethSepoliaToken), address(ethSepoliaPool));

        vm.stopPrank();

        //2 - Deploying the RebaseToken contract on the destination chain (Arbitrum Sepolia)
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)), // Using the same token for simplicity
            new address[](0), // No allowlist for simplicity
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        //a. Grant mint and burn role to our destination token
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        //b. Claim role on Arbitrum
        registryModuleOwnerCustomArbSepolia =
            RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress);
        registryModuleOwnerCustomArbSepolia.registerAdminViaOwner(address(arbSepoliaToken));

        //c. Accept the role on Arbitrum
        tokenAdminRegistryArbSepolia = TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress);
        tokenAdminRegistryArbSepolia.acceptAdminRole(address(arbSepoliaToken));

        //c. Link token to pool in the token admin registry on Sepolia
        tokenAdminRegistryArbSepolia.setPool(address(arbSepoliaToken), address(arbSepoliaPool));

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remainChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remainChainSelector,
            allowed: true,
            remotePoolAddress: remotePoolAddresses[0],
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
        vm.stopPrank();
    }
}
