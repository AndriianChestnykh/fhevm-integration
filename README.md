# Universal Privacy Layer for staking protocols

In this repo you can find a UniversalPrivacyLayer contract along with some token mocks for testing purposes.
The contract is designed to work with any ERC4626 compliant vault (e.g. Yearn Vaults). Only one such vault is supported at the moment and set via the constructor.
A user can deposit ERC20 tokens into the UniversalPrivacyLayer via the `deposit(...)` function, and then, in turn privately stake those tokens in the vault calling the `depositToVault(...)` function.
As long as many users request such a deposit to the vault there is an anonymity set because all the values are encrypted using FHE (Fully Homomorphic Encryption) and it is not publicly known how much each user has deposited.

With current implementation, it is assumed that there is special off-chain service, which will trigger the `initBulkDepositToVault(...)` functions to start depositing the total amount of the anonymity set to the vault.

Withdrawals are also private and exact amounts of each user to be withdrawn are not known to the public. The `withdrawFromVault(...)` function is used by user to request a withdrawal from the vault.
As long as many users requested such a withdrawal, there is an anonymity set of pending withdrawals and later the off-chain service can call `initBulkWithdrawFromVault(...)` to process all the pending withdrawals in one go.

There is also a `initWithdraw(...)` function, which can be called by user to request a withdrawal from the UniversalPrivacyLayer contract itself. 

# What is accomplished

- The UniversalPrivacyLayer contract itself
- Some unit tests for the contract

# What is not accomplished yet

- Frontend UI for the UniversalPrivacyLayer contract to deposit/withdraw and view the assets deposited and interest earned.
- Unit tests are do not cover the full cycle of deposits and withdrawals, so it is not clear if the approach is feasible and can work with current fhEVM limitations.
- Unit tests are failing when trying to call `depositToVault(...)` function with encrypted values. There are some issues with FHE values processing inside the contract.
- Most of the edge cases are not covered by unit tests.
- The contract does not support yield distribution yet. The solution is yet to figure out as there are some limitation with `FHE.div` operations is supported only with plaintext divisors.
- There is a `initBulkDepositToVault(...)` and `initBulkWithdrawFromVault(...)` functions with unlimited size of cycle iterations, which can lead to gas limit issues.
- The contract operates with `euint128` values but token contracts use `uint256` values, so there is a risk of overflow when converting between these types.
- The contract supports only one ERC4626 vault and one token at the moment.
