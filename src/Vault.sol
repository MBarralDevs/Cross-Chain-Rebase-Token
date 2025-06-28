// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {console} from "forge-std/console.sol";

contract Vault {
    //VARIABLES
    IRebaseToken private immutable i_rebaseToken;

    //ERRORS
    error Vault__InsufficientBalance();
    error Vault__RedeemFailed();

    //EVENTS
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    //CONSTRUCTOR
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    //FUNCTIONS

    receive() external payable {
        // This contract can receive Ether
    }

    function deposit() external payable {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        //effects - burn the user's rebase token
        i_rebaseToken.burn(msg.sender, _amount);

        //interactions - transfer the Ether back to the user
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }

        emit Redeem(msg.sender, _amount);
    }
    /**
     * @notice This function returns the address of the rebase token
     * @return The address of the rebase token
     */

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
