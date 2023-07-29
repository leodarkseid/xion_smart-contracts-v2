// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGPurchases {
    function setCashbackAddress(address _address) external;

    function setWallet(address _wallet) external;

    function setBridge(address _bridge, bool _active) external;

    function pause() external;

    function unpause() external;

    function transferOwnership(address newOwner) external;
}
