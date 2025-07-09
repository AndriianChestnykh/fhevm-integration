// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint128, externalEuint128, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UniversalPrivacyLayer is SepoliaConfig, Ownable2Step {
    using EnumerableMap for EnumerableMap.AddressToBytes32Map;

    IERC20 private immutable _asset;
    IERC4626 private immutable _vault;

    mapping(address user => euint128 balance) private _userBalances;
    mapping(address user => euint128 balance) private _vaultBalances;

    EnumerableMap.AddressToBytes32Map private _pendingDeposits;
    EnumerableMap.AddressToBytes32Map private _pendingWithdrawals;

    bool isBulkDepositDecryptionPending;
    bool isBulkWithdrawDecryptionPending;
    bool isWithdrawDecryptionPending;

    uint256 latestDepositRequestId;
    uint256 latestBulkWithdrawRequestId;
    uint256 latestWithdrawRequestId;

    constructor(IERC20 asset, IERC4626 vault, address owner) Ownable(owner) SepoliaConfig() {
        _asset = asset;
        _vault = vault;
    }

    function deposit(uint128 amount) external {
        euint128 encryptedAmount = FHE.asEuint128(amount);

        address caller = msg.sender;

        if (FHE.toBytes32(_userBalances[caller]) == bytes32(0)) {
            _userBalances[caller] = encryptedAmount;
        } else {
            _userBalances[caller] = FHE.add(_userBalances[caller], encryptedAmount);
        }
        SafeERC20.safeTransferFrom(IERC20(_asset), caller, address(this), amount);

        FHE.allowThis(_userBalances[caller]);
        FHE.allow(_userBalances[caller], caller);
    }

    function depositToVault(externalEuint128 inputAmount, bytes calldata inputProof) external {
        require(!isBulkDepositDecryptionPending, "Decryption is in progress");

        euint128 encryptedAmount = FHE.fromExternal(inputAmount, inputProof);

        address caller = msg.sender;
        ebool isInsufficient = FHE.lt(_userBalances[caller], encryptedAmount);
        euint128 originalBalance = euint128(_userBalances[caller]);
        _userBalances[caller] = FHE.select(
            isInsufficient,
            originalBalance,
            FHE.sub(euint128(_userBalances[caller]), encryptedAmount)
        );

        if (FHE.toBytes32(originalBalance) == FHE.toBytes32(_userBalances[caller])) {
            revert("Insufficient balance");
        }

        _pendingDeposits.set(caller, FHE.toBytes32(encryptedAmount));

        FHE.allowThis(_userBalances[caller]);
        FHE.allow(_userBalances[caller], caller);
        FHE.allow(euint128.wrap(_pendingDeposits.get(caller)), address(this));
    }

    function initBulkDepositToVault() external onlyOwner {
        require(!isBulkDepositDecryptionPending, "Decryption is in progress");

        euint128 totalEncryptedAmount = FHE.asEuint128(0);
        for (uint256 i = 0; i < _pendingDeposits.length(); i++) {
            (, bytes32 amount) = _pendingDeposits.at(i);
            euint128 encryptedAmount = euint128.wrap(amount);
            totalEncryptedAmount = FHE.add(totalEncryptedAmount, encryptedAmount);
        }

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(totalEncryptedAmount);
        latestDepositRequestId = FHE.requestDecryption(cts, this.finalizeBulkDepositToVaultCallback.selector);

        isBulkDepositDecryptionPending = true;
    }

    function finalizeBulkDepositToVaultCallback(
        uint256 requestId,
        uint128 amountToDeposit,
        bytes[] memory signatures
    ) external {
        require(requestId == latestDepositRequestId, "Invalid requestId");
        FHE.checkSignatures(requestId, signatures);

        _vault.deposit(amountToDeposit, address(this));

        for (uint256 i = 0; i < _pendingDeposits.length(); i++) {
            (address user, bytes32 amount) = _pendingDeposits.at(i);
            euint128 userVaultBalance = euint128(_vaultBalances[user]);
            euint128 newUserVaultBalance = FHE.add(userVaultBalance, euint128.wrap(amount));
            _vaultBalances[user] = newUserVaultBalance;
        }
        _pendingDeposits.clear();
        isBulkDepositDecryptionPending = false;
    }

    function initWithdraw(uint256 amount) external {
        require(!isWithdrawDecryptionPending, "Decryption is in progress");
        require(amount > 0, "Amount must be greater than zero");

        address caller = msg.sender;
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(_userBalances[caller]);
        latestBulkWithdrawRequestId = FHE.requestDecryption(cts, this.finalizeWithdrawCallback.selector);
        isWithdrawDecryptionPending = true;
    }

    function finalizeWithdrawCallback(uint256 requestId, uint128 amountToWithdraw, bytes[] memory signatures) external {
        require(requestId == latestBulkWithdrawRequestId, "Invalid requestId");
        FHE.checkSignatures(requestId, signatures);

        address caller = msg.sender;
        ebool notEnoughAmount = FHE.lt(_userBalances[caller], FHE.asEuint128(amountToWithdraw));
        euint128 originalBalance = _userBalances[caller];

        _userBalances[caller] = FHE.select(
            notEnoughAmount,
            _userBalances[caller],
            FHE.sub(_userBalances[caller], FHE.asEuint128(amountToWithdraw))
        );
        if (FHE.toBytes32(originalBalance) == FHE.toBytes32(_userBalances[caller])) {
            revert("Insufficient balance");
        }

        SafeERC20.safeTransferFrom(IERC20(_asset), address(this), caller, amountToWithdraw);

        FHE.allowThis(_userBalances[caller]);
        FHE.allow(_userBalances[caller], caller);
    }

    function withdrawFromVault(externalEuint128 inputAmount, bytes calldata inputProof) external {
        require(!isBulkWithdrawDecryptionPending, "Decryption is in progress");
        euint128 encryptedAmount = FHE.fromExternal(inputAmount, inputProof);

        address caller = msg.sender;
        ebool isInsufficient = FHE.lt(_vaultBalances[caller], encryptedAmount);
        euint128 originalBalance = _vaultBalances[caller];
        _vaultBalances[caller] = FHE.select(
            isInsufficient,
            _vaultBalances[caller],
            FHE.sub(_vaultBalances[caller], encryptedAmount)
        );

        if (FHE.toBytes32(originalBalance) == FHE.toBytes32(_vaultBalances[caller])) {
            revert("Insufficient vault balance");
        }

        _pendingWithdrawals.set(caller, FHE.toBytes32(encryptedAmount));

        FHE.allowThis(_vaultBalances[caller]);
        FHE.allow(_vaultBalances[caller], caller);
        FHE.allow(euint128.wrap(_pendingWithdrawals.get(caller)), caller);
    }

    function initBulkWithdrawFromVault() external onlyOwner {
        require(!isBulkWithdrawDecryptionPending, "Decryption is in progress");

        euint128 totalEncryptedAmount = FHE.asEuint128(0);
        for (uint256 i = 0; i < _pendingWithdrawals.length(); i++) {
            (, bytes32 amount) = _pendingWithdrawals.at(i);
            euint128 encryptedAmount = euint128.wrap(amount);
            totalEncryptedAmount = FHE.add(totalEncryptedAmount, encryptedAmount);
        }

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(totalEncryptedAmount);
        latestDepositRequestId = FHE.requestDecryption(cts, this.finalizeBulkWithdrawFromVaultCallback.selector);

        isBulkWithdrawDecryptionPending = true;
    }

    function finalizeBulkWithdrawFromVaultCallback(
        uint256 requestId,
        uint128 amountToWithdraw,
        bytes[] memory signatures
    ) external {
        require(requestId == latestBulkWithdrawRequestId, "Invalid requestId");
        FHE.checkSignatures(requestId, signatures);

        _vault.withdraw(amountToWithdraw, address(this), address(this));

        for (uint256 i = 0; i < _pendingWithdrawals.length(); i++) {
            (address user, bytes32 amount) = _pendingWithdrawals.at(i);

            _vaultBalances[user] = FHE.add(_vaultBalances[user], euint128.wrap(amount));
        }

        _pendingWithdrawals.clear();

        isBulkWithdrawDecryptionPending = false;
    }
}

// DO
// 1. Write NatSpec
// 2. Write unit tests

// TODO
// 1. Multi-token support
// 2. Multi-vault support
// 3. Can the privacy layer itself be a vault?
// 4. Zero amounts checks
// 5. Check if key was already present
// 6. Handle different amount when withdrawing from what was originally deposited, so manage privaty yield distribution
// 7. Make gas optimizations to avoid endless loops when requqesting decryption
// 8. Figure out how to check check if balance values fit uint128, as all token balances are uint256
// 9. Not sure if FHE.toBytes32(_userBalances[caller]) == bytes32(0) will work as expected with non existent keys

// NOTES
// 1. Integrate with ERC4626 but yVaults are compatible with ERC4626
