// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {console} from "forge-std/console.sol";

/**
 * @title RebaseToken
 * @author Martin BARRAL
 * @dev We are creation here a cross-chain rebase token
 * @dev This token will incentivize the user to deposit their token into a vault
 * @dev The interest rate present in the smart contract can only decrease
 * @dev The interest rate is set by a global interest rate at the time of deposit
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    //ERRORS
    error RebaseToken__InterestCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    //VARIABLES
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;

    //EVENTS
    event InterestRateChanged(uint256 oldInterestRate, uint256 newInterestRate);

    //CONSTRUCTOR
    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    //FUNCTIONS

    /**
     * @notice This function grants the mint and burn role to the account
     * @param _account The address of the account to grant the role to
     * @dev Only the owner can call this function
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice This function sets a new interest rate for the token
     * @param _newInterestRate The new interest rate to be set
     * @dev The interest rate can only decrease, not increase
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateChanged(s_interestRate, _newInterestRate);
    }

    /**
     * @notice This function returns the balance of the user. Number of token currently been minted to the user, not including any interest.
     * @return _user The user we want to get the principal balance of
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice This function mints tokens to the users after he deposited into the vault
     * @param _to The address to mint
     * @param _amount The amount of token to be minted
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice This function burns the users token after they withdraw from the vault
     * @param _from The address of the user to burn the token from
     * @param _amount The amount of token to be burned
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice This function returns the interest rate of the targeted user
     * @param _user The address of the user
     * @dev Use a mapping to store the interest rate of each user
     */
    function getUsersInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice This function returns the total balance of the targeted user, it means the total amount of token minted by this user
     * @param _user The address of the user
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        //We multiplie it by the accumulated interest of the user since the last update of the balance
        return currentPrincipalBalance * _calculateUserAccruedInterest(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice This function is overriding the ERC20 transfer function, it is used to transfer the token from one user to another
     * @param _recipient The address of the recipient
     * @param _amount The amount of token to be transferred
     * @return bool Returns true if the transfer was successful
     * @dev A known issue here is in case a user deposit a small amount of token in wallet1, then deposit a large amount in wallet2, and then transfer everything in wallet1, he will not get the interest rate of wallet2, but the interest rate of wallet1.
     * @dev This is not what we want, but it is a known issue with the current implementation of the rebase token.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        //We first mint the accrued interest of the user and recipient
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        //In case the recipient never interacted with the protocol, we set his interest rate to the current interest rate of msg.sender
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        //We then call the super transfer function to transfer the token
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        //We first mint the accrued interest of the user and recipient
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        //In case the recipient never interacted with the protocol, we set his interest rate to the current interest rate of msg.sender
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        //We then call the super transferFrom function to transfer the token
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice This function calcultate the accumulated interest of the user since the last update
     * @param _user The address of the user we want to calculate the interest
     * @dev This interest is going to be linear growth with time
     */
    function _calculateUserAccruedInterest(address _user) internal view returns (uint256 linearGrowth) {
        //1- Calculate the time since the last update
        uint256 timeSinceLastUpdate = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        //2- Calculate the linear growth amount
        linearGrowth = PRECISION_FACTOR + (s_userInterestRate[_user] * timeSinceLastUpdate);
    }

    /**
     * @notice This function mints the accrued interest of the user since the last interaction with the protocol
     * @param _user The address of the user we want to mint the interest for
     * @dev We use the balanceOf function to calculate the
     */
    function _mintAccruedInterest(address _user) internal {
        //We first get the principle balance of the user
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        //We then get the total balance of the user with the accumulated interest since the last update
        uint256 currentBalance = balanceOf(_user);

        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        s_userLastUpdatedTimeStamp[_user] = block.timestamp;

        //We mint the interest to the user
        _mint(_user, balanceIncrease);
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
