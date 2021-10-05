// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface ICashbackModule {
    function addCashback(address _recipient, uint256 _amount) external;
}
