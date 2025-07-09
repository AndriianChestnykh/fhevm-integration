// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract UniversalPrivacyLayer is SepoliaConfig {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    IERC20 private immutable _asset;
    IERC4626 private immutable _vault;

    mapping(address user => uint256 balance) private _userBalances;
    mapping(address user => uint256 balance) private _vaultBalances;

    EnumerableMap.AddressToUintMap private _pendingDeposits;
    EnumerableMap.AddressToUintMap private _pendingWithdrawals;

    function deposit(uint256 amount) external {
        address caller = msg.sender;
        _userBalances[caller] += amount; // to encrypt
        SafeERC20.safeTransferFrom(IERC20(_asset), caller, address(this), amount);
    }

    function initPrivateDepositToVault(uint256 amount) external {
        address caller = msg.sender;
        require(_userBalances[caller] >= amount, "Insufficient balance");
        _userBalances[caller] -= amount; // encrypted operation
        _pendingDeposits.set(caller, amount);
    }

    function finalizePrivateDepositToVault() external {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _pendingDeposits.length(); i++) {
            (address user, uint256 amount) = _pendingDeposits.at(i);
            totalAmount += amount; // encrypted operation
            _vaultBalances[user] += amount; // encrypted operation
        }
        _vault.deposit(totalAmount, address(this));
        _pendingDeposits.clear();
    }

    function withdraw(uint256 amount) external {
        address caller = msg.sender;
        require(_userBalances[caller] >= amount, "Insufficient balance"); // encrypted operation
        _userBalances[caller] -= amount; // encrypted operation
        SafeERC20.safeTransferFrom(IERC20(_asset), address(this), caller, amount);
    }

    function initPrivateWithdrawFromVault(uint256 amount) external {
        address caller = msg.sender;
        require(_vaultBalances[caller] >= amount, "Insufficient vault balance"); // encrypted operation
        _vaultBalances[caller] -= amount; // encrypted operation
        _pendingWithdrawals.set(caller, amount); // encrypted amount
    }

    function finalizePrivateWithdrawFromVault() external {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _pendingWithdrawals.length(); i++) {
            (address user, uint256 amount) = _pendingWithdrawals.at(i);
            totalAmount += amount; // encrypted operation
            _vaultBalances[user] -= amount; // encrypted amount
        }
        _vault.withdraw(totalAmount, address(this), address(this));
        _pendingWithdrawals.clear();
    }
}

// DO
// 1. Write NatSpec


// TODO
// 1. Multi-token support
// 2. Multi-vault support
// 3. Can the privacy layer itself be a vault?

// NOTES
// 1. Integrate with ERC4626 but yVaults are compatible with ERC4626