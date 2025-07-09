// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract ERC4626_mock is ERC4626 {
    constructor(IERC20 asset) ERC4626(asset) ERC20("Vault Token", "VT") {
    }
}
