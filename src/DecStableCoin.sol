// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin
contract DecStableCoin is ERC20Burnable, Ownable {
    error BurnAmountMustBeGreaterThanZero();
    error BurnAmountExceedsBalance();
    error NotZeroAddress();
    error MintAmountMustBeGreaterThanZero();

    constructor() ERC20("DecStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert BurnAmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert NotZeroAddress();
        }
        if (_amount <= 0) {
            revert MintAmountMustBeGreaterThanZero();
        }
        super._mint(_to, _amount);
        return true;
    }
}
