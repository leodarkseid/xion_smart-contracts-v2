// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IXGTFreezer.sol";
import "../interfaces/IXGHub.sol";
import "../interfaces/IStakingModule.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract XGWallet is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;

    IERC20 public xgt;
    IXGTFreezer public freezer;
    IStakingModule public staking;
    address public subscriptions;
    address public feeWallet;
    IXGHub public hub;
    address public purchases;

    uint256 public xdaiTotalCheckoutValue;
    uint256 public xgtTotalCheckoutValue;

    uint256 public FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP;
    uint256 public DEPOSIT_FEE_IN_BP;
    uint256 public WITHDRAW_FEE_IN_BP;

    mapping(address => bool) public stakeRevenue;
    mapping(address => UserBalanceSheet) public userBalance;
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public test;

    struct UserBalanceSheet {
        uint256 base;
        uint256 restrictedBase;
        uint256 xgt;
        uint256 restrictedXGT;
        uint256 merchantStakingShares;
        uint256 merchantStakingDeposits;
    }

    enum Currency {
        NULL,
        XDAI,
        XGT
    }

    function initialize(
        address _hub,
        address _xgt,
        address _freezer
    ) external initializer {
        hub = IXGHub(_hub);
        xgt = IERC20(_xgt);
        freezer = IXGTFreezer(_freezer);
        xgt.approve(_freezer, 2**256 - 1);

        FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP = 100;
        DEPOSIT_FEE_IN_BP = 0;
        WITHDRAW_FEE_IN_BP = 0;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(OwnableUpgradeable(address(hub)).owner());
    }

    function setFreezerContract(address _freezer) external onlyOwner {
        freezer = IXGTFreezer(_freezer);
        xgt.approve(_freezer, 2**256 - 1);
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

    function setFees(uint256 _depositFeeBP, uint256 _withdrawFeeBP)
        external
        onlyOwner
    {
        require(
            _depositFeeBP <= 10000 && _withdrawFeeBP <= 10000,
            "Can't have a fee over more than 100%"
        );
        DEPOSIT_FEE_IN_BP = _depositFeeBP;
        DEPOSIT_FEE_IN_BP = _withdrawFeeBP;
    }

    function setFeeWallet(address _feeWallet) external onlyHub {
        feeWallet = _feeWallet;
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

    fallback() external payable {
        _depositBase(msg.sender);
    }

    receive() external payable {
        _depositBase(msg.sender);
    }

    function deposit() external payable {
        _depositBase(msg.sender);
    }

    function depositForUser(address _user) public payable {
        _depositBase(_user);
    }

    function _depositBase(address _user) internal whenNotPaused {
        require(_user != address(0), "Empty address provided");
        uint256 fee = (msg.value.mul(DEPOSIT_FEE_IN_BP)).div(10000);
        if (fee > 0) {
            _transferXDai(feeWallet, fee);
        }
        userBalance[_user].base = userBalance[_user].base.add(
            msg.value.sub(fee)
        );
    }

    function depositXGT(uint256 _amount) external {
        _depositXGT(msg.sender, _amount);
    }

    function depositXGTForUser(address _user, uint256 _amount) external {
        _depositXGT(_user, _amount);
    }

    function _depositXGT(address _user, uint256 _amount)
        internal
        whenNotPaused
    {
        require(_user != address(0), "Empty address provided");
        uint256 fee = (_amount.mul(DEPOSIT_FEE_IN_BP)).div(10000);
        uint256 rest = _amount.sub(fee);
        if (fee > 0) {
            _transferFromXGT(_user, feeWallet, fee);
        }
        _transferFromXGT(_user, address(this), rest);
        userBalance[_user].xgt = userBalance[_user].xgt.add(rest);
    }

    function depositToRestrictredBaseBalanceOfUser(address _user)
        external
        payable
        whenNotPaused
    {
        require(_user != address(0), "Empty address provided");
        userBalance[_user].restrictedBase = userBalance[_user]
            .restrictedBase
            .add(msg.value);
        userBalance[_user].base = userBalance[_user].base.add(msg.value);
    }

    function depositToRestrictredXGTBalanceOfUser(
        address _user,
        uint256 _amount
    ) external whenNotPaused {
        require(_user != address(0), "Empty address provided");
        _transferFromXGT(_user, address(this), _amount);
        userBalance[_user].restrictedXGT = userBalance[_user].restrictedXGT.add(
            _amount
        );
        userBalance[_user].xgt = userBalance[_user].xgt.add(_amount);
    }

    function withdraw(uint256 _amount) public {
        _withdraw(msg.sender, _amount);
    }

    function withdrawForUser(address _user, uint256 _amount)
        public
        onlyAuthorized
    {
        _withdraw(_user, _amount);
    }

    function _withdraw(address _user, uint256 _amount) internal whenNotPaused {
        require(_user != address(0), "Empty address provided");
        require(
            _amount <=
                userBalance[_user].base.sub(userBalance[_user].restrictedBase),
            "Not enough in the users balance."
        );

        _removeFromBaseBalance(_user, _amount);
        if (_amount > 0) {
            uint256 fee = (_amount.mul(WITHDRAW_FEE_IN_BP)).div(10000);
            if (fee > 0) {
                _transferXDai(feeWallet, fee);
            }
            _transferXDai(_user, _amount.sub(fee));
        }
    }

    function withdrawXGT(uint256 _amount) public {
        _withdrawXGT(msg.sender, _amount);
    }

    function withdrawXGTForUser(address _user, uint256 _amount)
        public
        onlyAuthorized
    {
        _withdrawXGT(_user, _amount);
    }

    function _withdrawXGT(address _user, uint256 _amount)
        internal
        whenNotPaused
    {
        require(_user != address(0), "Empty address provided");
        require(
            _amount <=
                userBalance[_user].xgt.sub(userBalance[_user].restrictedXGT),
            "Not enough in the users balance."
        );
        _removeFromXGTBalance(_user, _amount);
        if (_amount > 0) {
            uint256 fee = (_amount.mul(WITHDRAW_FEE_IN_BP)).div(10000);
            if (fee > 0) {
                _transferXGT(feeWallet, fee);
            }
            _transferXGT(_user, _amount.sub(fee));
        }
    }

    function _transferXDai(address _receiver, uint256 _amount)
        internal
        whenNotPaused
    {
        uint256 balanceBefore = address(this).balance;
        bool success = false;
        (success, ) = payable(_receiver).call{value: _amount, gas: 2300}("");
        uint256 balanceAfter = address(this).balance;
        if (!success && balanceBefore.sub(balanceAfter) == 0) {
            (success, ) = payable(_receiver).call{value: _amount, gas: 20000}(
                ""
            );
            balanceAfter = address(this).balance;
        }
        require(
            success && balanceBefore.sub(balanceAfter) == _amount,
            "XDai Transfer failed."
        );
    }

    function _transferFromXGT(
        address _sender,
        address _receiver,
        uint256 _amount
    ) internal whenNotPaused {
        require(
            xgt.transferFrom(_sender, _receiver, _amount),
            "Token transferFrom failed."
        );
    }

    function _transferXGT(address _receiver, uint256 _amount)
        internal
        whenNotPaused
    {
        require(xgt.transfer(_receiver, _amount), "Token transfer failed.");
    }

    function payWithXGT(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _rate,
        bool _withFreeze,
        bool _useFallback
    ) external onlyModule returns (bool, uint256) {
        if (_amount == 0) {
            return (true, uint256(Currency.XGT));
        }
        uint256 xDaiEquivalent = (_amount.mul(_rate)).div(10**18);
        uint256 xgtLeft = _removeMaxFromXGTBalance(_from, _amount);

        // IF there is a rest from the calulcation above
        // we use their approved balance
        if (
            xgtLeft > 0 &&
            xgt.allowance(_from, address(this)) >= xgtLeft &&
            xgt.balanceOf(_from) >= xgtLeft
        ) {
            _transferFromXGT(_from, address(this), xgtLeft);
            xgtLeft = 0;
        }

        if (xgtLeft == 0) {
            _removeMaxFromRestrictedXGTBalance(_from, _amount);
            uint256 amountAfterFreeze = _amount;
            if (_withFreeze) {
                amountAfterFreeze = _freeze(_to, _amount);
            }
            if (stakeRevenue[_to]) {
                _stake(_to, amountAfterFreeze);
            } else {
                _transferXGT(_to, amountAfterFreeze);
            }
            xgtTotalCheckoutValue = xgtTotalCheckoutValue.add(_amount);
            return (true, uint256(Currency.XGT));
        }

        // IF not and IF the fallback is active, the user will be paying in XDai
        if (_useFallback && userBalance[_from].base >= xDaiEquivalent) {
            _removeFromBaseBalance(_from, xDaiEquivalent);
            _removeMaxFromRestrictedBaseBalance(_from, xDaiEquivalent);
            xdaiTotalCheckoutValue = xdaiTotalCheckoutValue.add(xDaiEquivalent);
            return (true, uint256(Currency.XDAI));
        }
        return (false, uint256(Currency.NULL));
    }

    function payWithXDai(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _rate,
        bool _withFreeze,
        bool _useFallback
    ) external onlyModule returns (bool, uint256) {
        if (_amount == 0) {
            return (true, uint256(Currency.XDAI));
        }
        // IF user has enough xdai balance, it will be used
        if (userBalance[_from].base >= _amount) {
            _removeFromBaseBalance(_from, _amount);
            _removeMaxFromRestrictedBaseBalance(_from, _amount);
            _transferXDai(_to, _amount);
            xdaiTotalCheckoutValue = xdaiTotalCheckoutValue.add(_amount);
            return (true, uint256(Currency.XDAI));
            // IF not and IF the fallback is active, the user will be paying in XGT
        } else if (_useFallback) {
            uint256 xgtEquivalent = (_amount.mul(10**18)).div(_rate);
            uint256 xgtLeft = _removeMaxFromXGTBalance(_from, xgtEquivalent);

            if (
                xgtLeft > 0 &&
                xgt.allowance(_from, address(this)) >= xgtLeft &&
                xgt.balanceOf(_from) >= xgtLeft
            ) {
                _transferFromXGT(_from, address(this), xgtLeft);
                xgtLeft = 0;
            }
            // If all of the XGT has been covered through the two options
            // the payment has been made, if not it will run into the last return at the bottom of the func
            if (xgtLeft == 0) {
                _removeMaxFromRestrictedXGTBalance(_from, xgtEquivalent);

                uint256 amountAfterFreeze = xgtEquivalent;
                if (_withFreeze) {
                    amountAfterFreeze = _freeze(_to, xgtEquivalent);
                }
                if (stakeRevenue[_to]) {
                    _stake(_to, amountAfterFreeze);
                } else {
                    _transferXGT(_to, amountAfterFreeze);
                }
                xgtTotalCheckoutValue = xgtTotalCheckoutValue.add(
                    xgtEquivalent
                );
                return (true, uint256(Currency.XGT));
            }
        }
        return (false, uint256(Currency.NULL));
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
            _transferXGT(_for, xgtAfter.sub(xgtBefore));
        }
    }

    function _removeFromBaseBalance(address _user, uint256 _amount) internal {
        userBalance[_user].base = userBalance[_user].base.sub(_amount);
    }

    function _removeFromRestrictedBaseBalance(address _user, uint256 _amount)
        internal
    {
        userBalance[_user].restrictedBase = userBalance[_user]
            .restrictedBase
            .sub(_amount);
    }

    function _removeMaxFromRestrictedBaseBalance(address _user, uint256 _amount)
        internal
    {
        if (_amount >= userBalance[_user].restrictedBase) {
            _removeFromRestrictedBaseBalance(
                _user,
                userBalance[_user].restrictedBase
            );
        } else {
            _removeFromRestrictedBaseBalance(_user, _amount);
        }
    }

    function _removeFromXGTBalance(address _user, uint256 _amount) internal {
        userBalance[_user].xgt = userBalance[_user].xgt.sub(_amount);
    }

    function _removeMaxFromXGTBalance(address _user, uint256 _amount)
        internal
        returns (uint256)
    {
        if (_amount >= userBalance[_user].xgt) {
            uint256 usedBalance = userBalance[_user].xgt;
            if (usedBalance > 0) {
                _removeFromXGTBalance(_user, usedBalance);
            }
            return _amount.sub(usedBalance);
        } else {
            _removeFromXGTBalance(_user, _amount);
            return 0;
        }
    }

    function _removeFromRestrictedXGTBalance(address _user, uint256 _amount)
        internal
    {
        userBalance[_user].restrictedXGT = userBalance[_user].restrictedXGT.sub(
            _amount
        );
    }

    function _removeMaxFromRestrictedXGTBalance(address _user, uint256 _amount)
        internal
    {
        if (_amount >= userBalance[_user].restrictedXGT) {
            _removeFromRestrictedXGTBalance(
                _user,
                userBalance[_user].restrictedXGT
            );
        } else {
            _removeFromRestrictedXGTBalance(_user, _amount);
        }
    }

    function getUserXGTBalance(address _user) external view returns (uint256) {
        uint256 xgtBalance = userBalance[_user].xgt;
        if (userBalance[_user].merchantStakingDeposits > 0) {
            (uint256 stakingBalance, , uint256 stakingShares) = staking
                .getCurrentUserInfo(address(this));
            xgtBalance = xgtBalance.add(
                stakingBalance
                    .mul(userBalance[_user].merchantStakingDeposits)
                    .div(stakingShares)
            );
        }
        return xgtBalance;
    }

    function getUserRestrictedXGTBalance(address _user)
        external
        view
        returns (uint256)
    {
        return userBalance[_user].restrictedXGT;
    }

    function getUserXDaiBalance(address _user) external view returns (uint256) {
        return userBalance[_user].base;
    }

    function getUserRestrictedXDaiBalance(address _user)
        external
        view
        returns (uint256)
    {
        return userBalance[_user].restrictedBase;
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
