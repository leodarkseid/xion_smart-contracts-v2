// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGTFreezer {
    function freeze(uint256 _amount) external;

    function freezeFor(address _recipient, uint256 _amount) external;

    function thaw() external;
}
