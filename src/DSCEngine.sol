// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecStableCoin} from "./DecStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// always: collateral > DSC
// we can set a threshold (150%) for the collateral to be greater than DSC
// if the user's collateral is less than 150% of the DSC, the user will get liquidated
// example:
// $50 DSC minted with $100 collateral. If user's collateral drops below $75 (e.g. $70), the user will get liquidated.
// another user can pay back the $50 DSC, and get the all the collateral left, $70 wins $20

contract DSCEngine is ReentrancyGuard {
    // errors
    error NeedsMoreThanZero();
    error TokenAndPriceFeedMustBeSameLength();
    error NotAllowedToken();
    error TransferFailed();
    error BreaksHealthFactor(uint256 healthFactor);
    error MintFailed();

    // state variables
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateral; // userToTokenToAmount
    mapping(address user => uint256 amountDscMinted) private s_userDsc; // userToDscAmount
    address[] private s_collateralTokens; // to register available collateral tokens

    DecStableCoin private immutable i_dsc;

    // events
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    // modifiers
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        // check if token is allowed
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert NotAllowedToken();
        }
        _;
    }

    // functions
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert TokenAndPriceFeedMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecStableCoin(dscAddress);
    }

    // // external
    function depositCollateralAndMintDsc() external {}

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // transfer token from user to this contract
        // add the amount to the user's collateral
        s_userCollateral[msg.sender][tokenCollateralAddress] += amountCollateral;
        // emit event
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function reedemCollateral() external {}

    // check if the user's collateral is greater than the threshold
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_userDsc[msg.sender] += amountDscToMint;
        _checkHealthFactor(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    // private and internal functions

    function _getUserInfo(address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_userDsc[user];
        collateralValueInUsd = getUserCollateralValue(user);
    }

    /**
     * Returns how close to liquidation the user is
     * If the health factor is less than 1, the user can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getUserInfo(user);
        // calculate the health factor
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return ((collateralAdjustedForThreshold * PRECISION) / totalDscMinted);
    }

    function _checkHealthFactor(address user) internal view {
        // check if the user's collateral is greater than the liquidation threshold
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert BreaksHealthFactor(healthFactor);
        }
    }

    //public and external view functions

    function getUserCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        totalCollateralValueInUsd = 0;
        // loop through the user's collateral
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_userCollateral[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256 valueUsd) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // price = priceInUsd * 1e8
        // amount in wei = amount * 1e18
        // to match the precision of the price feed, we multiply the amount by 1e10
        valueUsd = (uint256(price) * amount * ADDITIONAL_FEED_PRECISION) / PRECISION;
        return valueUsd;
    }
}
