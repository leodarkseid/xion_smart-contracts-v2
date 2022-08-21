// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGSubscriptions {
    function setFeeWallet(address _feeWallet) external;

    function setWallet(address _wallet) external;

    function pause() external;

    function unpause() external;

    function transferOwnership(address newOwner) external;
}
