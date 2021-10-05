// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ICashbackModule.sol";
import "../interfaces/IXGTFreezer.sol";
import "../interfaces/IXGWallet.sol";
import "../interfaces/IXGFeatureRegistry.sol";
import "../interfaces/IXGSubscriptions.sol";
import "../interfaces/IXGPurchases.sol";

contract XGHub is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    ICashbackModule public cashback;

    address public feeWallet;
    IERC20 public xgt;

    IXGWallet public wallet;
    IXGFeatureRegistry public features;
    IXGSubscriptions public subscriptions;
    IXGPurchases public purchases;

    mapping(address => bool) public authorized;

    function initialize(address _owner, address _xgt) external initializer {
        xgt = IERC20(_xgt);
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(_owner);
    }

    function updateWalletAddress(address _wallet) external onlyOwner {
        wallet = IXGWallet(_wallet);
    }

    function updateFeaturesAddress(address _features) external onlyOwner {
        features = IXGFeatureRegistry(_features);
    }

    function updateCashbackModule(address _cashbackModule) external onlyOwner {
        cashback = ICashbackModule(_cashbackModule);
        purchases.setCashbackAddress(_cashbackModule);
    }

    function updateSubscriptionsModule(address _subscriptionsModule)
        external
        onlyOwner
    {
        subscriptions = IXGSubscriptions(_subscriptionsModule);
        wallet.updateSubscriptionsContract(_subscriptionsModule);
    }

    function updatePurchasesModule(address _purchasesModule)
        external
        onlyOwner
    {
        purchases = IXGPurchases(_purchasesModule);
        wallet.updatePurchasesContract(_purchasesModule);
    }

    function updateFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
        wallet.updateFeeWallet(_feeWallet);
        subscriptions.setFeeWallet(_feeWallet);
    }

    function setAuthorizedAddress(address _address, bool _authorized)
        external
        onlyOwner
    {
        authorized[_address] = _authorized;
        wallet.setAuthorizedAddress(_address, _authorized);
        features.setAuthorizedAddress(_address, _authorized);
        subscriptions.setAuthorizedAddress(_address, _authorized);
        purchases.setAuthorizedAddress(_address, _authorized);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
        wallet.pause();
        features.pause();
        subscriptions.pause();
        purchases.pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
        wallet.unpause();
        features.unpause();
        subscriptions.unpause();
        purchases.unpause();
    }

    modifier onlyAuthorized() {
        require(
            authorized[msg.sender] || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }
}
