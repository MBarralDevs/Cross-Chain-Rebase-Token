// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address remoteAddress,
        uint64 destinationChainSelector,
        address localToken,
        uint256 amountToBridge,
        address linkTokenAddress,
        address routerAddress
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
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // We set the gas limit for the callback on the destination chain
        });

        //We need to get the fees for our ccip transaction
        uint256 fee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        console.log("CCIP Fee:", fee);

        //To finish we need to approve our router address to spend the link and local tokens
        uint256 feeBuffer = (fee * 110) / 100; // 10% buffer
        IERC20(linkTokenAddress).approve(routerAddress, feeBuffer);
        IERC20(localToken).approve(routerAddress, amountToBridge);

        if (IERC20(linkTokenAddress).balanceOf(msg.sender) < feeBuffer) {
            revert("Not enough LINK to pay CCIP fee");
        }

        //We call the ccipSend function to bridge the tokens
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
