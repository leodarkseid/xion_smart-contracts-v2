// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

// Baal: check version of openzeppelin
import "@openzeppelin/contracts-upgradeable@3.4.0/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts@3.4.0/token/ERC20/IERC20.sol";
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
        OwnableUpgradeable.transferOwnership(_owner);
    }

    function setWalletAddress(address _wallet) external onlyOwner {
        wallet = IXGWallet(_wallet);
        wallet.setSubscriptionsContract(address(subscriptions));
        wallet.setPurchasesContract(address(purchases));
    }

    function setFeaturesAddress(address _features) external onlyOwner {
        features = IXGFeatureRegistry(_features);
    }

    function setCashbackModule(address _cashbackModule) external onlyOwner {
        cashback = ICashbackModule(_cashbackModule);
        purchases.setCashbackAddress(_cashbackModule);
    }

    function setSubscriptionsModule(address _subscriptionsModule)
        external
        onlyOwner
    {
        subscriptions = IXGSubscriptions(_subscriptionsModule);
        subscriptions.setWallet(address(wallet));
        subscriptions.setFeeWallet(feeWallet);
        wallet.setSubscriptionsContract(_subscriptionsModule);
    }

    function setPurchasesModule(address _purchasesModule) external onlyOwner {
        purchases = IXGPurchases(_purchasesModule);
        purchases.setWallet(address(wallet));
        purchases.setCashbackAddress(address(cashback));
        wallet.setPurchasesContract(_purchasesModule);
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
        wallet.setFeeWallet(_feeWallet);
        subscriptions.setFeeWallet(_feeWallet);
    }

    function setBridge(address _bridge, bool _active) external onlyOwner {
        purchases.setBridge(_bridge, _active);
    }

    function setAuthorizedAddress(address _address, bool _authorized)
        external
        onlyOwner
    {
        authorized[_address] = _authorized;
    }

    function getAuthorizationStatus(address _address)
        public
        view
        returns (bool)
    {
        return authorized[_address];
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

    function transferOwnership(address newOwner) public override onlyOwner {
        OwnableUpgradeable.transferOwnership(newOwner);
        wallet.transferOwnership(newOwner);
        features.transferOwnership(newOwner);
        subscriptions.transferOwnership(newOwner);
        purchases.transferOwnership(newOwner);
    }

    modifier onlyAuthorized() {
        require(
            getAuthorizationStatus(msg.sender) || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }
}
