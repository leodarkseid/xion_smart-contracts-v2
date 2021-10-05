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

    function setAuthorizedAddress(address _address, bool _authorized) external;

    function pause() external;

    function unpause() external;

    function updateFeeWallet(address _feeWallet) external;

    function updateSubscriptionsContract(address _subscriptions) external;

    function updatePurchasesContract(address _purchases) external;
}
