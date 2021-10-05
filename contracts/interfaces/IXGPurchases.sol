// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGPurchases {
    function setAuthorizedAddress(address _address, bool _authorized) external;

    function setCashbackAddress(address _address) external;

    function pause() external;

    function unpause() external;
}
