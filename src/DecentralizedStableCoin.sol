//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title DecentralizedStableCoin
 * @author Theodoros Zarkalis
 * Collateral : Exogenous (ETH and BTC)
 * Minting : Algorithmic
 * Relative Stability : Pegged to USD
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // Custom errors
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__InefficientBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    // Simple constrcutor that just calls the ERC20 constructor given the name and symbol
    // of our token and sets the deployer as the owner of the contract
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    // Overriding the burn function to add a check for the amount of tokens
    function burn(uint256 _amount) public override onlyOwner {
        // Check if the amount is more than 0
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        // Also check if the amount is more than the balance
        if (_amount > balance) {
            revert DecentralizedStableCoin__InefficientBalance();
        }
        // If all is good, call the burn function from the parent contract
        super.burn(_amount);
    }

    // Overriding the mint function to add a check for the amount of tokens
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        // Check if the address to which the tokens are being minted is not zero address
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        // Check if the amount is more than 0
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        // If all is good, call the mint function from the parent contract
        _mint(_to, _amount);
        // And also return true, to indicate that the minting was successful
        return true;
    }
}
