// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

// Baal: check version of openzeppelin
import "@openzeppelin/contracts-upgradeable@3.4.0/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/utils/PausableUpgradeable.sol";
import "../interfaces/IXGWallet.sol";
import "../interfaces/IXGHub.sol";
import "../interfaces/IDateTime.sol";

contract XGSubscriptions is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    IXGWallet public wallet;
    IXGHub public hub;
    IDateTime public dateTimeLib;
    address public feeWallet;

    enum Status {
        NULL,
        ACTIVE,
        PAUSED,
        UNSUBSCRIBED,
        END
    }

    struct Subscription {
        address user;
        address merchant;
        bytes32 productId;
        bytes32 parentProductId;
        Status status;
        bool unlimited;
        uint256 billingDay;
        uint256 nextBillingDay;
        uint256 billingCycle;
        uint256 cycles;
        uint256 price;
        uint256 successPaymentsAmount;
        uint256 lastPaymentDate;
    }

    mapping(bytes32 => Subscription) public subscriptions;
    mapping(bytes32 => bool) public productPaused;

    event SubscriptionCreated(
        address user,
        address merchant,
        bytes32 subscriptionId,
        uint256 processID,
        bytes32 productId
    );

    event SubscriptionPaid(
        address user,
        address merchant,
        bytes32 subscriptionID,
        uint256 rebillID,
        address tokenAddress,
        uint256 tokenPayment,
        uint256 tokenPrice
    );

    event PauseSubscriptionByCustomer(
        address user,
        bytes32 subscriptionID,
        uint256 processID,
        uint256 currency,
        uint256 tokenPrice
    );

    event ActivateSubscription(
        address user,
        bytes32 subscriptionID,
        uint256 processID
    );

    event CancelSubscription(
        address user,
        bytes32 subscriptionID,
        uint256 processID
    );

    event PauseProductByMerchant(bytes32 productID, uint256 processID);
    event UnpauseProductByMerchant(bytes32 productID, uint256 processID);

    event PauseSubscriptionByMerchant(
        bytes32 subscriptionID,
        uint256 processID
    );
    event UnpauseSubscriptionByMerchant(
        bytes32 subscriptionID,
        uint256 processID
    );

    function initialize(address _hub, address _dateTimeLib)
        external
        initializer
    {
        hub = IXGHub(_hub);
        dateTimeLib = IDateTime(_dateTimeLib);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(OwnableUpgradeable(address(hub)).owner());
    }

    function setXGHub(address _hub) external onlyOwner {
        hub = IXGHub(_hub);
    }

    function setFeeWallet(address _feeWallet) external onlyHub {
        feeWallet = _feeWallet;
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

    function subscribeUser(
        address user,
        address merchant,
        bytes32 subscriptionId,
        bytes32 productId,
        uint256 processID,
        uint256 billingDay,
        uint256 billingCycle,
        uint256 cycles,
        address tokenAddress,
        uint256[] calldata priceInfo, // price, basePayment, tokenPayment, tokenPrice
        bool unlimited,
        bytes32 parentProductId
    ) public onlyAuthorized whenNotPaused {
        require(
            !productPaused[productId] &&
                !productPaused[subscriptions[subscriptionId].parentProductId],
            "Product paused by merchant"
        );
        require(
            subscriptions[subscriptionId].status != Status.ACTIVE,
            "User already has an active subscription with this ID"
        );
        require(billingDay <= 28, "Invalid billing day");

        subscriptions[subscriptionId] = Subscription(
            user,
            merchant,
            productId,
            parentProductId,
            Status.ACTIVE,
            unlimited,
            billingDay,
            0,
            billingCycle,
            cycles,
            priceInfo[0],
            0,
            0
        );
        emit SubscriptionCreated(
            user,
            merchant,
            subscriptionId,
            processID,
            productId
        );
        processSubscriptionPayment(
            subscriptionId,
            0,
            tokenAddress,
            priceInfo[2],
            priceInfo[3]
        );
    }

    function processSubscriptionPayment(
        bytes32 subscriptionId,
        uint256 rebillID,
        address tokenAddress,
        uint256 tokenPayment,
        uint256 tokenPrice
    ) public onlyAuthorized whenNotPaused {
        uint256 tokenPaymentValue = (tokenPayment.mul(tokenPrice)).div(10**18);
        require(
            (subscriptions[subscriptionId].successPaymentsAmount <
                subscriptions[subscriptionId].cycles) ||
                subscriptions[subscriptionId].unlimited,
            "Subscription is over"
        );
        require(
            (tokenPaymentValue <= subscriptions[subscriptionId].price),
            "Payment cant be more than started payment amount"
        );
        require(
            !productPaused[subscriptions[subscriptionId].productId],
            "Product paused by merchant"
        );
        require(
            subscriptions[subscriptionId].status != Status.UNSUBSCRIBED &&
                subscriptions[subscriptionId].status != Status.PAUSED,
            "Subscription must not be unsubscribed or paused"
        );

        require(
            block.timestamp >= subscriptions[subscriptionId].nextBillingDay,
            "Subscription can't be rebilled before the next billing date"
        );
        if (subscriptions[subscriptionId].billingDay != 0) {
            uint8 month = dateTimeLib.getMonth(block.timestamp);
            uint16 year = dateTimeLib.getYear(block.timestamp);
            if (month == 12) {
                month = 1;
                year++;
            } else {
                month++;
            }
            subscriptions[subscriptionId].nextBillingDay = dateTimeLib
                .toTimestamp(
                    year,
                    month,
                    uint8(subscriptions[subscriptionId].billingDay),
                    0,
                    0,
                    0
                );
        } else {
            if (subscriptions[subscriptionId].nextBillingDay == 0) {
                subscriptions[subscriptionId].nextBillingDay = block.timestamp;
            }
            subscriptions[subscriptionId].nextBillingDay = subscriptions[
                subscriptionId
            ].nextBillingDay.add(subscriptions[subscriptionId].billingCycle);
        }

        bool success = wallet.payWithToken(
            tokenAddress,
            subscriptions[subscriptionId].user,
            subscriptions[subscriptionId].merchant,
            tokenPayment,
            true
        );

        require(success, "Payment failed");

        subscriptions[subscriptionId].status = Status.ACTIVE;
        subscriptions[subscriptionId].lastPaymentDate = block.timestamp;
        subscriptions[subscriptionId].successPaymentsAmount = subscriptions[
            subscriptionId
        ].successPaymentsAmount.add(1);

        if (
            subscriptions[subscriptionId].successPaymentsAmount ==
            subscriptions[subscriptionId].cycles &&
            !subscriptions[subscriptionId].unlimited
        ) {
            subscriptions[subscriptionId].status = Status.END;
        }

        emit SubscriptionPaid(
            subscriptions[subscriptionId].user,
            subscriptions[subscriptionId].merchant,
            subscriptionId,
            rebillID,
            tokenAddress,
            tokenPayment,
            tokenPrice
        );
    }

    function pauseProductAsMerchant(bytes32 productId, uint256 processID)
        public
        onlyAuthorized
        whenNotPaused
    {
        productPaused[productId] = true;
        emit PauseProductByMerchant(productId, processID);
    }

    function unpauseProductAsMerchant(bytes32 productId, uint256 processID)
        public
        onlyAuthorized
        whenNotPaused
    {
        productPaused[productId] = false;
        emit UnpauseProductByMerchant(productId, processID);
    }

    function unsubscribeAsMerchant(
        bytes32[] calldata subscriptionIds,
        uint256 processID
    ) public onlyAuthorized whenNotPaused {
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            cancelSubscription(subscriptionIds[i], processID);
        }
    }

    function resubscribeAsMerchant(
        bytes32[] calldata subscriptionIds,
        uint256 processID
    ) public onlyAuthorized whenNotPaused {
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            activateSubscription(subscriptionIds[i], processID);
        }
    }

    function pauseSubscriptionsAsMerchant(
        bytes32[] calldata subscriptionIds,
        uint256 processID
    ) public onlyAuthorized whenNotPaused {
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            bytes32 subscription = subscriptionIds[i];
            require(
                subscriptions[subscription].status != Status.PAUSED &&
                    subscriptions[subscription].status != Status.UNSUBSCRIBED,
                "Subscription is already paused"
            );

            subscriptions[subscription].status = Status.PAUSED;
            emit PauseSubscriptionByMerchant(subscription, processID);
            (subscriptions[subscription].productId, processID);
        }
    }

    function unpauseSubscriptionsAsMerchant(
        bytes32[] calldata subscriptionIds,
        uint256 processID
    ) public onlyAuthorized whenNotPaused {
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            bytes32 subscription = subscriptionIds[i];
            require(
                subscriptions[subscription].status == Status.PAUSED &&
                    subscriptions[subscription].status != Status.UNSUBSCRIBED,
                "Subscription is not paused"
            );

            subscriptions[subscription].status = Status.ACTIVE;
            emit UnpauseSubscriptionByMerchant(
                subscriptions[subscription].productId,
                processID
            );
        }
    }

    function cancelSubscription(bytes32 subscriptionId, uint256 processID)
        public
        onlyAuthorized
        whenNotPaused
    {
        if (
            subscriptions[subscriptionId].status == Status.ACTIVE ||
            subscriptions[subscriptionId].status == Status.PAUSED
        ) {
            subscriptions[subscriptionId].status = Status.UNSUBSCRIBED;

            emit CancelSubscription(
                subscriptions[subscriptionId].user,
                subscriptionId,
                processID
            );
        }
    }

    function pauseSubscription(
        bytes32 subscriptionId,
        uint256 processID,
        address tokenAddress,
        uint256 tokenPrice
    ) public onlyAuthorized whenNotPaused {
        require(
            subscriptions[subscriptionId].status != Status.PAUSED &&
                subscriptions[subscriptionId].status != Status.UNSUBSCRIBED,
            "Subscription is already paused"
        );

        subscriptions[subscriptionId].status = Status.PAUSED;

        uint256 totalValue = subscriptions[subscriptionId].price.mul(125).div(
            1000
        );
        uint256 merchantValue = subscriptions[subscriptionId]
            .price
            .mul(100)
            .div(1000);

        uint256 totalTokens = (totalValue.mul(10**18)).div(tokenPrice);
        uint256 merchantAmount = (merchantValue.mul(10**18)).div(
            tokenPrice
        );
        bool successMerchant = wallet.payWithToken(
            tokenAddress,
            subscriptions[subscriptionId].user,
            subscriptions[subscriptionId].merchant,
            merchantAmount,
            true
        );
        require(successMerchant, "Pause payment to merchant failed.");
        bool successFee = wallet.payWithToken(
            tokenAddress,
            subscriptions[subscriptionId].user,
            feeWallet,
            totalTokens.sub(merchantAmount),
            false
        );
        require(successFee, "Pause payment to fee wallet failed.");
        emit PauseSubscriptionByCustomer(
            subscriptions[subscriptionId].user,
            subscriptionId,
            processID,
            uint256(IXGWallet.Currency.XGT),
            tokenPrice
        );
    }

    function activateSubscription(bytes32 subscriptionId, uint256 processID)
        public
        onlyAuthorized
        whenNotPaused
    {
        require(
            subscriptions[subscriptionId].status != Status.UNSUBSCRIBED,
            "Subscription must be unsubscribed"
        );
        subscriptions[subscriptionId].status = Status.ACTIVE;
        emit ActivateSubscription(
            subscriptions[subscriptionId].user,
            subscriptionId,
            processID
        );
    }

    function getSubscriptionStatus(bytes32 subscriptionId)
        external
        view
        returns (uint256)
    {
        return uint256(subscriptions[subscriptionId].status);
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
