// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

// Baal: check version of openzeppelin
import "@openzeppelin/contracts-upgradeable@3.4.0/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/utils/PausableUpgradeable.sol";
import "../interfaces/ICashbackModule.sol";
import "../interfaces/IXGWallet.sol";
import "../interfaces/IXGHub.sol";
import "../interfaces/IDateTime.sol";

contract XGPurchases is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    ICashbackModule public cashback;
    IXGWallet public wallet;
    IXGHub public hub;
    mapping (address => bool) public bridges;

    struct Purchase {
        address user;
        address merchant;
        bytes32 productId;
        bytes32 parentProductId;
        uint256 date;
        uint256 price;
        bool paid;
    }

    mapping(bytes32 => Purchase) public purchases;

    event PurchasePaid(
        address user,
        address merchant,
        bytes32 subscriptionID,
        uint256 processID,
        uint256 currency,
        uint256 tokenPayment,
        uint256 tokenPrice
    );

    event ConfirmDepositForPurchase(
        uint256 id, 
        address userDestinationAddress, 
        uint256 amountUsd
    );

    function initialize(address _hub) external initializer {
        hub = IXGHub(_hub);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(OwnableUpgradeable(address(hub)).owner());
    }

    function setCashbackAddress(address _cashbackModule) external onlyHub {
        cashback = ICashbackModule(_cashbackModule);
    }

    function setXGHub(address _hub) external onlyOwner {
        hub = IXGHub(_hub);
    }

    function setWallet(address _wallet) external onlyHub {
        wallet = IXGWallet(_wallet);
    }

    function setBridge(address _bridge, bool _active) external onlyHub {
        bridges[_bridge] = _active;
    }

    function pause() external onlyHub whenNotPaused {
        _pause();
    }

    function unpause() external onlyHub whenPaused {
        _unpause();
    }

    function processPurchase(
        address user,
        address merchant,
        bytes32 purchaseId,
        bytes32 productId,
        bytes32 parentProductId,
        uint256 processID,
        uint256 price,
        address tokenAddress,
        uint256 tokenPayment,
        uint256 tokenPrice,
        address bridgeWallet
    ) public onlyAuthorized whenNotPaused {
        purchases[purchaseId] = Purchase(
            user,
            merchant,
            productId,
            parentProductId,
            block.timestamp,
            price,
            false
        );
        processOneTimePayment(
            purchaseId,
            processID,
            tokenAddress,
            tokenPayment,
            tokenPrice,
            bridgeWallet
        );
    }

    function processOneTimePayment(
        bytes32 purchaseId,
        uint256 processID,
        address tokenAddress,
        uint256 tokenPayment,
        uint256 tokenPrice,
        address bridgeWallet
    ) public onlyAuthorized whenNotPaused {
        uint256 tokenPaymentValue = (tokenPayment.mul(tokenPrice)).div(10**18);
        require(
            tokenPaymentValue <= purchases[purchaseId].price,
            "Payment cant be more then started payment amount"
        );

        require(!purchases[purchaseId].paid, "Already paid");

        uint256 currencyUsed = uint256(IXGWallet.Currency.NULL);
        require(wallet.payWithToken(
                tokenAddress,
                purchases[purchaseId].user,
                purchases[purchaseId].merchant,
                tokenPayment,
                bridgeWallet,
                purchaseId
            ), "Payment failed");

        purchases[purchaseId].paid = true;

        if (address(cashback) != address(0)) {
            cashback.addCashback(purchases[purchaseId].user, tokenPaymentValue);
        }

        emit PurchasePaid(
            purchases[purchaseId].user,
            purchases[purchaseId].merchant,
            purchaseId,
            processID,
            currencyUsed,
            tokenPayment,
            tokenPrice
        );
    }

    function confirmDepositForPurchase(
        uint256 id, 
        address userDestinationAddress, 
        uint256 amountUsd
    ) external onlyBridge {
        emit ConfirmDepositForPurchase(id, userDestinationAddress, amountUsd);
    }

    modifier onlyAuthorized() {
        require(
            hub.getAuthorizationStatus(msg.sender) || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    modifier onlyHub() {
        require(msg.sender == address(hub), "Not authorized");
        _;
    }

    modifier onlyBridge() {
        require(bridges[msg.sender], "Not authorized");
        _;
    }
}
