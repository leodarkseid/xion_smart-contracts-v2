// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract XGTFreezer {
    using SafeMath for uint256;

    IERC20 public xgt;
    uint256 public constant FROZEN_UNTIL = 4133984400; // UTC 1st of January 2100
    mapping(address => uint256) frozenBalance;
    uint256 totalFrozen = 0;

    constructor(address _token) {
        xgt = IERC20(_token);
    }

    function freeze(uint256 _amount) external {
        _freeze(msg.sender, _amount);
    }

    function freezeFor(address _recipient, uint256 _amount) external {
        _freeze(_recipient, _amount);
    }

    function _freeze(address _recipient, uint256 _amount) internal {
        require(_recipient != address(0), "Invalid address");
        require(
            xgt.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );
        frozenBalance[_recipient] = frozenBalance[_recipient].add(_amount);
        totalFrozen = totalFrozen.add(_amount);
    }

    function thaw() external {
        require(block.timestamp >= FROZEN_UNTIL, "Tokens are still frozen");
        uint256 userBalance = frozenBalance[msg.sender];
        frozenBalance[msg.sender] = 0;
        totalFrozen = totalFrozen.sub(userBalance);
        if (userBalance > 0) {
            require(xgt.transfer(msg.sender, userBalance), "Transfer failed");
        }
    }
}
