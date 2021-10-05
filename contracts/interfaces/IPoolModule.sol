// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IPoolModule {
    function claimModule(address _user) external;

    function getClaimable(address _user) external view returns (uint256);

    function getPoolValue(uint256 _id) external view returns (uint256);

    function getTotalValue() external view returns (uint256);

    function getCurrentAverageXGTPrice() external view returns (uint256);
}
