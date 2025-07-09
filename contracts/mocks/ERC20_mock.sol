// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20_mock is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
