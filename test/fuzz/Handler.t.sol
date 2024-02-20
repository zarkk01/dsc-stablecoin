//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test , console } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Handler is going to narrow down the way the functions are called
contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address[] collateralTokens;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 constant MAX_DEPOSIT = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    // Here, we gonna pass random numbers instead of random addresses, because it is easier to predict
    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) external {
        // Like that we take the address of the collateral token but it is random which one
        ERC20Mock collateralToken = _getCollateralFromSeeds(collateralSeed);
        // Here, we bound the amount to be between 1 and MAX_DEPOSIT
        uint256 collateralBounded = bound(collateralAmount, 1, MAX_DEPOSIT);

        // We mint some fake ERC20Mock selected tokens to the user and we approve contract to sent them,
        // so we can simulate the deposit of them as collateral in dsce
        collateralToken.mint(msg.sender, collateralBounded);
        vm.startPrank(msg.sender);
        // Here, is the approval to the dsce contract to take the tokens from the user
        collateralToken.approve(address(dsce), collateralBounded);
        // And finally we deposit the tokens as collateral
        dsce.depositCollateral(address(collateralToken), collateralBounded);
        vm.stopPrank();
    }

    // Helper functions

    // With this function we only get valid addresses as collateral, either wbtc or weth
    function _getCollateralFromSeeds(uint256 seed) private view returns (ERC20Mock) {
        if ( seed % 2 == 0 ) {
            return weth;
        } else {
            return wbtc;
        }
    }
}