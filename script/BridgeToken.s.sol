// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract BridgeToken is Script {
    function run(
        address localToken,
        address remoteAddress,
        uint64 destinationChainSelector,
        address routerAddress,
        uint256 amountToBridge,
        address linkTokenAddress
    ) public {
        vm.startBroadcast();
        //Creating EVMTokenAmount necessary for the EVM2AnyMessage
        Client.EVMTokenAmount[] memory tokenAmount = new Client.EVMTokenAmount[](1);
        tokenAmount[0] = Client.EVMTokenAmount({token: localToken, amount: amountToBridge});

        //To be able to call the ccipSend function, we need to create an EVM2AnyMessage
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(remoteAddress), // The remote address is the destination address for the token bridge
            data: "", // We don't need to specify data for token bridging
            tokenAmounts: tokenAmount, // The token amounts to bridge
            feeToken: linkTokenAddress, // The LINK token address is used to pay for the CCIP fees
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000})) // We set the gas limit for the callback on the destination chain
        });

        //We call the ccipSend function to bridge the tokens
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
