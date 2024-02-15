//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author Zark
 * This contract is meant to be as minimal as possible and have
 *  the token to be pegged == $1
 * This stablecoin has the properties:
 * 1. Collateral : Exogenous (ETH and BTC)
 * 2. Minting : Algorithmic
 * 3. Relative Stability : Pegged to USD
 *
 * This stablecoin should be always "over-collateralized". At no point should the
 * value of the collateral be less than the value of the stablecoin.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for the mining
 *  and redeeming DSC, as well as depositing and withdrawing collateral. Also based on DAI System.
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NotZero();
    error DSCEngine__NotAllowedCollateral();
    error DSCEngine__NotEqualLength();
    error DSCEngine__TransferFailed();

    mapping(address token => address priceFeed) public s_priceFeeds;
    mapping(address userAddress => mapping(address tokenAddress => uint256 amount)) public s_collateralBalances;

    DecentralizedStableCoin public immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    modifier notZero(uint256 _value) {
        if (_value == 0) {
            revert DSCEngine__NotZero();
        }
        _;
    }

    modifier isAllowedCollateral(address _tokenCollateralAddress) {
        if (s_priceFeeds[_tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedCollateral();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__NotEqualLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        notZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralBalances[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemDSCAForDsc() external {}

    function redeemCollateral() external {}

    function mindDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
