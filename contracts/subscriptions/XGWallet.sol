// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable@3.4.0/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/utils/PausableUpgradeable.sol";
import "../interfaces/IXGTFreezer.sol";
import "../interfaces/IXGHub.sol";
import "../interfaces/IStakingModule.sol";

import "@openzeppelin/contracts@3.4.0/token/ERC20/IERC20.sol";

contract XGWallet is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address public XGT_ADDRESS = 0xC25AF3123d2420054c8fcd144c21113aa2853F39;
    IERC20 public xgt = IERC20(XGT_ADDRESS);

    address[] public tokenAddresses;
    mapping (address => IERC20) public tokens;
    IXGTFreezer public freezer;
    IStakingModule public staking;
    address public subscriptions;
    address public feeWallet;
    address public bridgeFeeWallet;
    IXGHub public hub;
    address public purchases;

    mapping (address => uint256) public totalCheckoutValue;

    uint256 public FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP;
    uint256 public DEPOSIT_FEE_IN_BP;
    uint256 public WITHDRAW_FEE_IN_BP;
    uint256 public PAYMENT_FEE_IN_BP;
    uint256 public BRIDGE_FEE_IN_BP;

    mapping (address => uint256) public merchantFeeInBP;
    mapping (address => address) public merchantParent;

    mapping(address => bool) public stakeRevenue;
    mapping(address => UserBalanceSheet) public userBalance;
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public test;

    struct UserBalanceSheet {
        mapping (address => uint256) balances;
        mapping (address => uint256) restrictedBalances;
        uint256 merchantStakingShares;
        uint256 merchantStakingDeposits;
    }

    function initialize(
        address _hub,
        address _freezer,
        address[] calldata _tokens
    ) external initializer {
        hub = IXGHub(_hub);
        freezer = IXGTFreezer(_freezer);
        for (uint256 i; i < _tokens.length; ++i) {
            tokenAddresses.push(_tokens[i]);
            tokens[_tokens[i]] = IERC20(_tokens[i]);
        }
        xgt.approve(_freezer, 2**256 - 1);

        FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP = 100;
        DEPOSIT_FEE_IN_BP = 0;
        WITHDRAW_FEE_IN_BP = 0;
        PAYMENT_FEE_IN_BP = 0;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(OwnableUpgradeable(address(hub)).owner());
    }

    function setFreezerContract(address _freezer) external onlyOwner {
        freezer = IXGTFreezer(_freezer);
        xgt.approve(_freezer, 2**256 - 1);
    }

    function setSupportedToken(address _token) external onlyOwner {
        require(address(tokens[_token]) == address(0), "Token must not already be supported");
        tokenAddresses.push(_token);
        tokens[_token] = IERC20(_token);
        if (_token == XGT_ADDRESS) {
            xgt.approve(address(freezer), 2**256 - 1);
        }
    }

    function setXGHub(address _hub) external onlyOwner {
        hub = IXGHub(_hub);
    }

    function setStakingModule(address _stakingModule) external onlyOwner {
        staking = IStakingModule(_stakingModule);
    }

    function setSubscriptionsContract(address _subscriptions) external onlyHub {
        subscriptions = _subscriptions;
    }

    function setPurchasesContract(address _purchases) external onlyHub {
        purchases = _purchases;
    }

    function setFrozenAmountMerchant(uint256 _freezeBP) external onlyOwner {
        require(_freezeBP <= 10000, "Can't freeze more than 100%");
        FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP = _freezeBP;
    }

    function setFees(uint256 _depositFeeBP, uint256 _withdrawFeeBP, uint256 _paymentFeeBP, uint256 _bridgeFeeBP)
        external
        onlyOwner
    {
        require(
            _depositFeeBP <= 10000 && _withdrawFeeBP <= 10000 && _paymentFeeBP <= 10000 && _bridgeFeeBP <= 10000,
            "Can't have a fee over more than 100%"
        );
        DEPOSIT_FEE_IN_BP = _depositFeeBP;
        WITHDRAW_FEE_IN_BP = _withdrawFeeBP;
        PAYMENT_FEE_IN_BP = _paymentFeeBP;
        BRIDGE_FEE_IN_BP = _bridgeFeeBP;
    }

    function setMerchantParent(address _merchant, address _parent)
        public
        onlyOwner
    {
        require(
            _merchant != address(0),
            "Merchant address cannot be zero"
        );
        merchantParent[_merchant] = _parent;
    }

    function setMerchantFee(address _merchant, uint256 _paymentFeeBP)
        public
        onlyOwner
    {
        require(
            _paymentFeeBP <= 10000,
            "Can't have a fee over more than 100%"
        );
        merchantFeeInBP[_merchant] = _paymentFeeBP;
    }

    function setMerchantInfo(address _merchant, address _parent, uint256 _paymentFeeBP)
        external
        onlyOwner
    {
        setMerchantFee(_merchant, _paymentFeeBP);
        setMerchantParent(_merchant, _parent);
    }

    function setFeeWallet(address _feeWallet) external onlyHub {
        feeWallet = _feeWallet;
    }

    function setBridgeFeeWallet(address _bridgeFeeWallet) external onlyOwner {
        bridgeFeeWallet = _bridgeFeeWallet;
    }

    function toggleStakeRevenue(bool _stakeRevenue) external {
        _unstake(msg.sender);
        stakeRevenue[msg.sender] = _stakeRevenue;
    }

    function toggleStakeRevenueForUser(address _user, bool _stakeRevenue)
        external
        onlyAuthorized
    {
        _unstake(_user);
        stakeRevenue[_user] = _stakeRevenue;
    }

    function pause() external onlyHub whenNotPaused {
        _pause();
    }

    function unpause() external onlyHub whenPaused {
        _unpause();
    }

    function depositToken(address _token, uint256 _amount) external {
        _depositToken(msg.sender, msg.sender, _token, _amount);
    }

    function depositTokenForUser(address _user, address _token, uint256 _amount) external {
        _depositToken(_user, _user, _token, _amount);
    }

    function depositTokenOnBehalfOfUser(address _user, address _token, uint256 _amount) external {
        _depositToken(msg.sender, _user, _token, _amount);
    }

    function _depositToken(address _payer, address _user, address _token, uint256 _amount)
        internal
        whenNotPaused
    {
        require(address(tokens[_token]) != address(0), "Token must be supported");
        require(_user != address(0), "Empty address provided");
        uint256 fee = (_amount.mul(DEPOSIT_FEE_IN_BP)).div(10000);
        uint256 rest = _amount.sub(fee);
        if (fee > 0) {
            _transferFromToken(_token, _payer, feeWallet, fee);
        }
        _transferFromToken(_token, _payer, address(this), rest);
        userBalance[_user].balances[_token] = userBalance[_user].balances[_token].add(rest);
    }

    function depositToRestrictedTokenBalanceOfUser(
        address _user,
        address _token,
        uint256 _amount
    ) external whenNotPaused {
        require(address(tokens[_token]) != address(0), "Token must be supported");
        require(_user != address(0), "Empty address provided");
        _transferFromToken(_token, _user, address(this), _amount);
        userBalance[_user].restrictedBalances[_token] = userBalance[_user].restrictedBalances[_token].add(
            _amount
        );
        userBalance[_user].balances[_token] = userBalance[_user].balances[_token].add(_amount);
    }

    function withdrawToken(address _token, uint256 _amount) public {
        _withdrawToken(msg.sender, _token, _amount);
    }

    function withdrawUSDTForUser(address _user, address _token, uint256 _amount)
        public
        onlyAuthorized
    {
        _withdrawToken(_user, _token, _amount);
    }

    function _withdrawToken(address _user, address _token, uint256 _amount)
        internal
        whenNotPaused
    {
        require(address(tokens[_token]) != address(0), "Token must be supported");
        require(_user != address(0), "Empty address provided");
        require(
            _amount <=
                userBalance[_user].balances[_token].sub(userBalance[_user].restrictedBalances[_token]),
            "Not enough in the users balance."
        );
        _removeFromTokenBalance(_user, _token, _amount);
        if (_amount > 0) {
            uint256 fee = (_amount.mul(WITHDRAW_FEE_IN_BP)).div(10000);
            if (fee > 0) {
                _transferToken(_token, feeWallet, fee);
            }
            _transferToken(_token, _user, _amount.sub(fee));
        }
    }

    function _transferFromToken(
        address _token, 
        address _sender,
        address _receiver,
        uint256 _amount
    ) internal whenNotPaused {
        require(address(tokens[_token]) != address(0), "Token must be supported");
        if (_amount > 0) {
            require(
                tokens[_token].transferFrom(_sender, _receiver, _amount),
                "Token transferFrom failed."
            );
        }
    }

    function _transferToken(address _token, address _receiver, uint256 _amount)
        internal
        whenNotPaused
    {
        require(address(tokens[_token]) != address(0), "Token must be supported");
        if (_amount > 0) {
            require(tokens[_token].transfer(_receiver, _amount), "Token transfer failed.");
        }
    }

    function payWithToken(
        address _token, 
        address _from,
        address _to,
        uint256 _amount,
        bool _withFreeze
    ) external onlyModule returns (bool) {
        require(address(tokens[_token]) != address(0), "Token must be supported");
        if (_amount == 0) {
            return true;
        }
        uint256[3] memory fees; // xionFee, bridgeFee, merchantFees

        fees[0] = (_amount.mul(PAYMENT_FEE_IN_BP)).div(10000);
        fees[1] = (_amount.mul(BRIDGE_FEE_IN_BP)).div(10000);

        address current = _to;
        while (current != address(0)) {
            fees[2] = fees[2].add((_amount.mul(merchantFeeInBP[current])).div(10000));
            current = merchantParent[current];
        }
        uint256 leftover = _amount.sub(fees[0]).sub(fees[1]).sub(fees[2]);

        uint256 tokensLeft = _removeMaxFromTokenBalance(_from, _token, _amount);

        if (
            tokensLeft > 0 &&
            tokens[_token].allowance(_from, address(this)) >= tokensLeft &&
            tokens[_token].balanceOf(_from) >= tokensLeft
        ) {
            _transferFromToken(_token, _from, address(this), tokensLeft);
            tokensLeft = 0;
        }

        if (tokensLeft == 0) {
            _removeMaxFromRestrictedTokenBalance(_token, _from, _amount);
            uint256 amountAfterFreeze = _amount;
            if (_withFreeze && _token == XGT_ADDRESS) {
                amountAfterFreeze = _freeze(_to, _amount);
            }
            if (stakeRevenue[_to]) {
                _stake(_to, amountAfterFreeze);
            } else {
                _transferFromToken(_token, _from, feeWallet, fees[0]);
                _transferFromToken(_token, _from, bridgeFeeWallet, fees[1]);
                current = _to;
                while (current != address(0)) {
                    _transferToken(_token, current, (_amount.mul(merchantFeeInBP[current])).div(10000));
                    current = merchantParent[current];
                }
                _transferToken(_token, _to, leftover);
            }
            // does not include any fees!
            totalCheckoutValue[_token] = totalCheckoutValue[_token].add(_amount);
            return true;
        }

        return false;
    }

    function _freeze(address _to, uint256 _amount)
        internal
        whenNotPaused
        returns (uint256)
    {
        uint256 freezeAmount = _amount
            .mul(FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP)
            .div(10000);
        freezer.freezeFor(_to, freezeAmount);
        return _amount.sub(freezeAmount);
    }

    function _stake(address _for, uint256 _amount) internal whenNotPaused {
        (, , uint256 sharesBefore) = staking.getCurrentUserInfo(address(this));
        xgt.approve(address(staking), _amount);
        staking.depositForUser(address(this), _amount, true);
        (, , uint256 sharesAfter) = staking.getCurrentUserInfo(address(this));
        userBalance[_for].merchantStakingShares = userBalance[_for]
            .merchantStakingShares
            .add(sharesAfter.sub(sharesBefore));
        userBalance[_for].merchantStakingDeposits = userBalance[_for]
            .merchantStakingDeposits
            .add(_amount);
    }

    function _unstake(address _for) internal whenNotPaused {
        if (userBalance[_for].merchantStakingShares > 0) {
            uint256 xgtBefore = xgt.balanceOf(address(this));
            uint256 withdrawShares = userBalance[_for].merchantStakingShares;
            userBalance[_for].merchantStakingShares = 0;
            userBalance[_for].merchantStakingDeposits = 0;
            staking.withdraw(withdrawShares);
            uint256 xgtAfter = xgt.balanceOf(address(this));
            _transferToken(XGT_ADDRESS, _for, xgtAfter.sub(xgtBefore));
        }
    }

    function _removeFromTokenBalance(address _user, address _token, uint256 _amount) internal {
        userBalance[_user].balances[_token] = userBalance[_user].balances[_token].sub(_amount);
    }

    function _removeMaxFromTokenBalance(address _user, address _token, uint256 _amount)
        internal
        returns (uint256)
    {
        if (_amount >= userBalance[_user].balances[_token]) {
            uint256 usedBalance = userBalance[_user].balances[_token];
            if (usedBalance > 0) {
                _removeFromTokenBalance(_user, _token, usedBalance);
            }
            return _amount.sub(usedBalance);
        } else {
            _removeFromTokenBalance(_user, _token, _amount);
            return 0;
        }
    }

    function _removeFromRestrictedTokenBalance(address _user, address _token, uint256 _amount)
        internal
    {
        userBalance[_user].restrictedBalances[_token] = userBalance[_user].restrictedBalances[_token].sub(
            _amount
        );
    }

    function _removeMaxFromRestrictedTokenBalance(address _user, address _token, uint256 _amount)
        internal
    {
        if (_amount >= userBalance[_user].restrictedBalances[_token]) {
            _removeFromRestrictedTokenBalance(
                _user,
                _token,
                userBalance[_user].restrictedBalances[_token]
            );
        } else {
            _removeFromRestrictedTokenBalance(_user, _token, _amount);
        }
    }

    function getUserTokenBalance(address _token, address _user) external view returns (uint256) {
        uint256 tokenBalance = userBalance[_user].balances[_token];
        if (_token == XGT_ADDRESS && userBalance[_user].merchantStakingDeposits > 0) {
            (uint256 stakingBalance, , uint256 stakingShares) = staking
                .getCurrentUserInfo(address(this));
            tokenBalance = tokenBalance.add(
                stakingBalance
                    .mul(userBalance[_user].merchantStakingDeposits)
                    .div(stakingShares)
            );
        }
        return tokenBalance;
    }

    function getUserRestrictedTokenBalance(address _user, address _token)
        external
        view
        returns (uint256)
    {
        return userBalance[_user].restrictedBalances[_token];
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

    modifier onlyModule() {
        require(
            msg.sender == subscriptions ||
                msg.sender == purchases ||
                msg.sender == address(hub),
            "Not authorized"
        );
        _;
    }
}
