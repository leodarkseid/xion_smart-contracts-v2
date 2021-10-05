# Xion Global Smart Contracts

The Xion Global smart contracts running on the xDai chain powering the Xion Global shopping ecosystem.

## Smart Contracts

### XGHub

The hub contract is the central contract of the Xion Global architecture. It links to the latest individual modules and serves as the interaction point for important functions.

The hub also features general security functions like `pause()`, `unpause()` or `setAuthorizedAddress()`. The important and nice part about these functions is, that they automatically invoke the same function in every module. So if (in an emergency) the multi-sig calls the `pause` function of the hub, every module will automatically be paused in the same transaction. 

You can find the contract [here](https://github.com/xion-global/xionfinance_smartcontract/blob/master/contracts/subscriptions/XGHub.sol).

### XGWallet

The wallet contract implements all the necessary features related to payments and funds. Users can `deposit` xDai as well as <img src="https://xion.finance/images/xgt_icon.png" width="12" height="12"> XGT in order to these funds to buy goods and services. Users can also `withdraw()` their funds at any time, which was important to us.

The other modules of the XG contract suite can interact with the wallet to process payments and pay out merchants. These functions (like `payWithXGT` or `payWithXDai`) can only be called via one of the other modules.

You can find the contract [here](https://github.com/xion-global/xionfinance_smartcontract/blob/master/contracts/subscriptions/XGWallet.sol).

### XGFeatureRegistry

The Xion Global platform offers some features that have to be unlocked via a small payment in either xDai or XGT. The status of these features can be recorded for each user or merchant via the feature registry contract. E.g. the `toggleFeatureUnlock()` would be called by the backend to indicate that someone has unlocked a certain feature. The unlocked features of a user can be retrieved via functions like `getUnlockedFeaturesOfUser()`.

In the future, we are potentially planning to upgrade this contract such that the unlocked features are represented via NFTs.

You can find the contract [here](https://github.com/xion-global/xionfinance_smartcontract/blob/master/contracts/subscriptions/XGFeatureRegistry.sol).

### XGSubscriptions

One of the corner stones of the Xion Global platform is the ability to handle subscriptions via the blockchain. This is implemented in the subscriptions contract. It offers functions like `subscribeUser()`, `processSubscriptionPayment()`, `pauseSubscription()` and `cancelSubscription()`. These functions are currently called by our backend (to save gas for the user). In the future, we also want to allow our users to call these functions directly.

The payments themselves are routed through the wallet contract mentioned above.

You can find the contract [here](https://github.com/xion-global/xionfinance_smartcontract/blob/master/contracts/subscriptions/XGSubscriptions.sol).

### XGPurchases

The second important part of the Xion Global platform are single billing purchases. These are handles by the purchases contract, offering simple functions like `processPurchase()` or `processOneTimePayment()`. The corresponding payment and potential cashback mechanism is handled by the wallet contract mentioned above.

You can find the contract [here](https://github.com/xion-global/xionfinance_smartcontract/blob/master/contracts/subscriptions/XGPurchases.sol).

### Upgradeability

We are leveraging the Upgradeability features by OpenZeppelin, allowing us to introduce features without changing the contract's address as well as fixing any unforeseen bugs that could lead to a financial loss for our users. The safety of our users and consequently their funds is of utmost importance to us!
However, we are **not** using this feature for the token itself, in order to maintain decentralization and not even having the possibility to gain access to our users funds.

## License

[GNU Affero General Public License v3.0](https://github.com/xion-global/xionfinance_smartcontract/blob/master/LICENSE)
