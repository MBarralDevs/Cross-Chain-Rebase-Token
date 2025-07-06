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
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    //States variables
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;
    uint256 public SEND_VALUE = 1e5;

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
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        // bytes[] memory remotePoolAddresses = new bytes[](1);
        // remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(address(remotePool)),
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
        vm.stopPrank();
    }

    //Setup function to bridge tokens between two chains
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        vm.startPrank(user);

        //Creating EVMTokenAmount necessary for the EVM2AnyMessage
        Client.EVMTokenAmount[] memory tokenAmount = new Client.EVMTokenAmount[](1);
        tokenAmount[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        //Creating the message to be sent cross-chain
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmount,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });
        vm.stopPrank();

        //Giving the user some LINK tokens to pay for the fee
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            user, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );

        vm.startPrank(user);

        //Approving the router address to spend link tokens + local tokens
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        uint256 localBalanceBefore = IERC20(address(localToken)).balanceOf(user);

        //Sending our message cross-chain with ccipSend
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        //Checking that the local token balance has been reduced by the amount bridged
        uint256 localBalanceAfter = IERC20(address(localToken)).balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);

        uint256 localInterestRate = localToken.getUserInterestRate(user);
        vm.stopPrank();

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 900); // Simulating the time for the message to be processed (15min)
        //Getting the user's arbitrum sep token balance before the message is processed
        uint256 remoteBalanceBefore = IERC20(address(remoteToken)).balanceOf(user);

        vm.selectFork(localFork);
        //Switching the chain to arbSepolia and routing the message
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        //Checkin that the user's remote token balance has been updated
        uint256 remoteBalanceAfter = IERC20(address(remoteToken)).balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);

        //Checking that the user's interest rate on the remote token is the same as the local token
        uint256 remoteInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(remoteInterestRate, localInterestRate);

        vm.stopPrank();
    }

    //Test function to bridge tokens between two chains (ETH Sepolia and Arbitrum Sepolia)
    function testBridgeAllTokens() public {
        //Configuring the token pools for both chains
        configureTokenPool(
            ethSepoliaFork,
            ethSepoliaPool,
            arbSepoliaPool,
            IRebaseToken(address(arbSepoliaToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            arbSepoliaPool,
            ethSepoliaPool,
            IRebaseToken(address(ethSepoliaToken)),
            ethSepoliaNetworkDetails
        );

        vm.selectFork(ethSepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);

        //Depositing some ETH into the vault to get the Sepolia RebaseToken
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(IERC20(address(ethSepoliaToken)).balanceOf(user), SEND_VALUE);
        vm.stopPrank();

        //Bridging the tokens from ETH Sepolia to Arbitrum Sepolia
        bridgeTokens(
            SEND_VALUE,
            ethSepoliaFork,
            arbSepoliaFork,
            ethSepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            ethSepoliaToken,
            arbSepoliaToken
        );

        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 900); // Simulating the time for the message to be processed (15min)

        //Bridging the tokens from Arbitrum Sepolia to ETH Sepolia
        bridgeTokens(
            SEND_VALUE,
            arbSepoliaFork,
            ethSepoliaFork,
            arbSepoliaNetworkDetails,
            ethSepoliaNetworkDetails,
            arbSepoliaToken,
            ethSepoliaToken
        );
    }
}
