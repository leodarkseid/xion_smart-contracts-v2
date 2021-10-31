// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGHub {
    function getAuthorizationStatus(address _address)
        external
        view
        returns (bool);
}
