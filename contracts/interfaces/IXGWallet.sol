// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

interface IXGWallet {
    enum Currency {
        NULL,
        XDAI,
        XGT
    }

    function payWithXGT(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _rate,
        bool _withFreeze,
        bool _useFallback
    ) external returns (bool, uint256);

    function payWithXDai(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _rate,
        bool _withFreeze,
        bool _useFallback
    ) external returns (bool, uint256);

    function getCustomerXGTBalance(address _user)
        external
        view
        returns (uint256);

    function getCustomerXDaiBalance(address _user)
        external
        view
        returns (uint256);

    function pause() external;

    function unpause() external;

    function setFeeWallet(address _feeWallet) external;

    function setSubscriptionsContract(address _subscriptions) external;

    function setPurchasesContract(address _purchases) external;

    function transferOwnership(address newOwner) external;
}
