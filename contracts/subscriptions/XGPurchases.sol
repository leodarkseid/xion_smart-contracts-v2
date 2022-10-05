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
        uint256 basePayment,
        uint256 tokenPayment,
        uint256 tokenPrice
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
        uint256 basePayment,
        uint256 tokenPayment,
        uint256 tokenPrice
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
            basePayment,
            tokenPayment,
            tokenPrice
        );
    }

    function processOneTimePayment(
        bytes32 purchaseId,
        uint256 processID,
        uint256 basePayment,
        uint256 tokenPayment,
        uint256 tokenPrice
    ) public onlyAuthorized whenNotPaused {
        uint256 tokenPaymentValue = (tokenPayment.mul(tokenPrice)).div(10**18);
        uint256 totalValue = basePayment.add(tokenPaymentValue);
        require(
            totalValue <= purchases[purchaseId].price,
            "Payment cant be more then started payment amount"
        );

        require(!purchases[purchaseId].paid, "Already paid");

        uint256 currencyUsed = uint256(IXGWallet.Currency.NULL);
        bool success = false;
        if (basePayment > 0) {
            (success, currencyUsed) = wallet.payWithXDai(
                purchases[purchaseId].user,
                purchases[purchaseId].merchant,
                basePayment,
                tokenPrice,
                true,
                false
            );
        } else {
            (success, currencyUsed) = wallet.payWithXGT(
                purchases[purchaseId].user,
                purchases[purchaseId].merchant,
                tokenPayment,
                tokenPrice,
                true,
                false
            );
        }
        require(success, "Payment failed");

        purchases[purchaseId].paid = true;

        if (address(cashback) != address(0)) {
            cashback.addCashback(purchases[purchaseId].user, totalValue);
        }

        emit PurchasePaid(
            purchases[purchaseId].user,
            purchases[purchaseId].merchant,
            purchaseId,
            processID,
            currencyUsed,
            basePayment,
            tokenPayment,
            tokenPrice
        );
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
}
