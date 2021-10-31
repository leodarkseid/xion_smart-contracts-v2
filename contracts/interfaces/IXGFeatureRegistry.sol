// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGFeatureRegistry {
    function pause() external;

    function unpause() external;

    function transferOwnership(address newOwner) external;
}
