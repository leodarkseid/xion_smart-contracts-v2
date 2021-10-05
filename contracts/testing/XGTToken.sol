// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract XGTTestToken is ERC20 {
    using SafeMath for uint256;

    // Total Token Supply
    uint256 public constant MAX_SUPPLY = 1000000000 * 10**18; // 1 billion

    constructor() ERC20("Test Token", "XTT") {
        require(totalSupply() == 0, "XGT-ALREADY-INITIALIZED");
        _mint(msg.sender, MAX_SUPPLY);
        require(totalSupply() == MAX_SUPPLY, "XGT-INVALID-SUPPLY");
    }
}
