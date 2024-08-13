// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DecStableCoin} from "../../src/DecStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    DecStableCoin dsc;
    DSCEngine dsce;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateral;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        usersWithCollateral.push(msg.sender);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        // Check health factor before allowing redemption
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        uint256 collateralValueAfterRedemption =
            collateralValueInUsd - dsce.getUsdValue(address(collateral), amountCollateral);
        uint256 newHealthFactor = dsce.calculateHealthFactor(totalDscMinted, collateralValueAfterRedemption);

        if (newHealthFactor < dsce.getMinHealthFactor()) {
            return; // Exit if redeeming would break health factor
        }
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 userSeed) public {
        if (usersWithCollateral.length == 0) {
            return;
        }
        address user = getUserFromSeed(userSeed);
        console.log("UserXd: ", user);
        vm.startPrank(user);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        console.log("totalDscMinted: ", totalDscMinted);
        console.log("collateralValueInUsd: ", collateralValueInUsd);
        // uint256 healthFactor = dsce.calculateHealthFactor(totalDscMinted, collateralValueInUsd);
        // console.log("healthFactor: ", healthFactor);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted); // calculates the overcollateralization of user in dsc
        if (maxDscToMint < 0) {
            // if user is undercollateralized, don't mint
            return;
        }
        // bound the amount to mint to the max amount user can mint
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        dsce.mintDsc(amount);
        timesMintIsCalled++;
        vm.stopPrank();
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function getUserFromSeed(uint256 seed) public view returns (address) {
        return usersWithCollateral[seed % usersWithCollateral.length];
    }
}
