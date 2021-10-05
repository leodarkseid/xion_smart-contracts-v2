// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IXGTFreezer.sol";
import "../interfaces/IXGSubscriptions.sol";
import "../interfaces/IStakingModule.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract XGWallet is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;

    IERC20 public xgt;
    IXGTFreezer public freezer;
    IStakingModule public staking;
    IXGSubscriptions public subscriptions;
    address public feeWallet;
    address public hub;
    address public purchases;

    uint256 public FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP;
    uint256 public DEPOSIT_FEE_IN_BP;
    uint256 public WITHDRAW_FEE_IN_BP;

    mapping(address => bool) public authorized;
    mapping(address => bool) public stakeRevenue;
    mapping(address => uint256) public customerBalancesBase;
    mapping(address => uint256) public customerBalancesXGT;
    mapping(address => uint256) public merchantStakingShares;
    mapping(address => uint256) public merchantStakingDeposits;

    enum Currency {
        NULL,
        XDAI,
        XGT
    }

    function initialize(
        address _hub,
        address _xgt,
        address _freezer,
        address _feeWallet,
        address _owner
    ) external initializer {
        hub = _hub;
        xgt = IERC20(_xgt);
        freezer = IXGTFreezer(_freezer);
        xgt.approve(_freezer, 2**256 - 1);
        feeWallet = _feeWallet;

        FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP = 100;
        DEPOSIT_FEE_IN_BP = 0;
        WITHDRAW_FEE_IN_BP = 0;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(_owner);
    }

    function updateFreezerContract(address _freezer) external onlyOwner {
        freezer = IXGTFreezer(_freezer);
        xgt.approve(_freezer, 2**256 - 1);
    }

    function updateXGHub(address _hub) external onlyOwner {
        hub = _hub;
    }

    function updateStakingModule(address _stakingModule) external onlyOwner {
        staking = IStakingModule(_stakingModule);
    }

    function updateSubscriptionsContract(address _subscriptions)
        external
        onlyHub
    {
        subscriptions = IXGSubscriptions(_subscriptions);
    }

    function updatePurchasesContract(address _purchases) external onlyHub {
        purchases = _purchases;
    }

    function updateFrozenAmountMerchant(uint256 _freezeBP) external onlyOwner {
        require(_freezeBP <= 10000, "Can't freeze more than 100%");
        FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP = _freezeBP;
    }

    function updateFees(uint256 _depositFeeBP, uint256 _withdrawFeeBP)
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

    function updateFeeWallet(address _feeWallet) external onlyHub {
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

    function setAuthorizedAddress(address _address, bool _authorized)
        external
        onlyHub
    {
        authorized[_address] = _authorized;
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
        customerBalancesBase[_user] = customerBalancesBase[_user].add(
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
        customerBalancesXGT[_user] = customerBalancesXGT[_user].add(rest);
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

    function _withdraw(address _user, uint256 _amount) internal {
        require(_user != address(0), "Empty address provided");
        require(
            _amount <= customerBalancesBase[_user],
            "Not enough in the users balance."
        );
        customerBalancesBase[_user] = customerBalancesBase[_user].sub(_amount);
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

    function _withdrawXGT(address _user, uint256 _amount) internal {
        require(_user != address(0), "Empty address provided");
        require(
            _amount <= customerBalancesXGT[_user],
            "Not enough in the users balance."
        );
        customerBalancesXGT[_user] = customerBalancesXGT[_user].sub(_amount);
        if (_amount > 0) {
            uint256 fee = (_amount.mul(WITHDRAW_FEE_IN_BP)).div(10000);
            if (fee > 0) {
                _transferXGT(feeWallet, fee);
            }
            _transferXGT(_user, _amount.sub(fee));
        }
    }

    function _transferXDai(address _receiver, uint256 _amount) internal {
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
    ) internal {
        require(
            xgt.transferFrom(_sender, _receiver, _amount),
            "Token transferFrom failed."
        );
    }

    function _transferXGT(address _receiver, uint256 _amount) internal {
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
        uint256 xgtLeft = _amount;

        // IF user has enough xgt balance, it will be used
        if (customerBalancesXGT[_from] >= _amount) {
            if (customerBalancesXGT[_from] >= _amount) {
                customerBalancesXGT[_from] = customerBalancesXGT[_from].sub(
                    _amount
                );
                xgtLeft = 0;
                // IF the users customer balance ƒ XGT is not enough
                // it will be used up and the rest will be paid via transfer
            } else {
                xgtLeft = xgtLeft.sub(customerBalancesXGT[_from]);
                customerBalancesXGT[_from] = 0;
            }

            // IF there is a rest from the calulcation above
            // we use their approved balance
            if (
                xgtLeft > 0 &&
                xgt.allowance(_from, address(this)) >= xgtLeft &&
                xgt.balanceOf(_from) >= xgtLeft
            ) {
                _transferFromXGT(_from, address(this), xgtLeft);
            }
            // If all of the XGT has been covered through the two options
            // the payment has been made, if not it will run into the last return at the bottom of the func
            if (xgtLeft == 0) {
                uint256 amountAfterFreeze = _amount;
                if (_withFreeze) {
                    amountAfterFreeze = _freeze(_to, _amount);
                }
                if (stakeRevenue[_to]) {
                    _stake(_to, amountAfterFreeze);
                } else {
                    _transferXGT(_to, amountAfterFreeze);
                }
                return (true, uint256(Currency.XGT));
            }
            // IF not and IF the fallback is active, the user will be paying in XDai
        } else if (
            _useFallback && customerBalancesBase[_from] >= xDaiEquivalent
        ) {
            customerBalancesBase[_from] = customerBalancesBase[_from].sub(
                xDaiEquivalent
            );
            _transferXDai(_to, xDaiEquivalent);
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
        if (customerBalancesBase[_from] >= _amount) {
            customerBalancesBase[_from] = customerBalancesBase[_from].sub(
                _amount
            );
            _transferXDai(_to, _amount);
            return (true, uint256(Currency.XDAI));
            // IF not and IF the fallback is active, the user will be paying in XGT
        } else if (_useFallback) {
            uint256 xgtEquivalent = (_amount.mul(10**18)).div(_rate);
            uint256 xgtLeft = xgtEquivalent;
            // IF the user has XGT in their customer balance, it will be used
            if (customerBalancesXGT[_from] > 0) {
                if (customerBalancesXGT[_from] >= xgtEquivalent) {
                    customerBalancesXGT[_from] = customerBalancesXGT[_from].sub(
                        xgtEquivalent
                    );
                    xgtLeft = 0;
                    // IF the users customer balance of XGT is not enough
                    // it will be used up and the rest will be paid via transfer
                } else {
                    xgtLeft = xgtLeft.sub(customerBalancesXGT[_from]);
                    customerBalancesXGT[_from] = 0;
                }
            }
            // IF there is a rest from the calulcation above
            // we use their approved balance
            if (
                xgtLeft > 0 &&
                xgt.allowance(_from, address(this)) >= xgtLeft &&
                xgt.balanceOf(_from) >= xgtLeft
            ) {
                _transferFromXGT(_from, address(this), xgtLeft);
            }
            // If all of the XGT has been covered through the two options
            // the payment has been made, if not it will run into the last return at the bottom of the func
            if (xgtLeft == 0) {
                uint256 amountAfterFreeze = xgtEquivalent;
                if (_withFreeze) {
                    amountAfterFreeze = _freeze(_to, xgtEquivalent);
                }
                if (stakeRevenue[_to]) {
                    _stake(_to, amountAfterFreeze);
                } else {
                    _transferXGT(_to, amountAfterFreeze);
                }
                return (true, uint256(Currency.XGT));
            }
        }
        return (false, uint256(Currency.NULL));
    }

    function _freeze(address _to, uint256 _amount) internal returns (uint256) {
        uint256 freezeAmount = _amount
            .mul(FREEZE_PERCENT_OF_MERCHANT_PAYMENT_IN_BP)
            .div(10000);
        freezer.freezeFor(_to, freezeAmount);
        return _amount.sub(freezeAmount);
    }

    function _stake(address _for, uint256 _amount) internal {
        (, , uint256 sharesBefore) = staking.getCurrentUserInfo(address(this));
        xgt.approve(address(staking), _amount);
        staking.depositForUser(address(this), _amount, true);
        (, , uint256 sharesAfter) = staking.getCurrentUserInfo(address(this));
        merchantStakingShares[_for] = merchantStakingShares[_for].add(
            sharesAfter.sub(sharesBefore)
        );
        merchantStakingDeposits[_for] = merchantStakingDeposits[_for].add(
            _amount
        );
    }

    function _unstake(address _for) internal {
        if (merchantStakingShares[_for] > 0) {
            uint256 xgtBefore = xgt.balanceOf(address(this));
            uint256 withdrawShares = merchantStakingShares[_for];
            merchantStakingShares[_for] = 0;
            merchantStakingDeposits[_for] = 0;
            staking.withdraw(withdrawShares);
            uint256 xgtAfter = xgt.balanceOf(address(this));
            _transferXGT(_for, xgtAfter.sub(xgtBefore));
        }
    }

    function getUserXGTBalance(address _user) external view returns (uint256) {
        uint256 xgtBalance = customerBalancesXGT[_user];
        if (merchantStakingShares[_user] > 0) {
            (uint256 stakingBalance, , uint256 stakingShares) = staking
                .getCurrentUserInfo(address(this));
            xgtBalance = xgtBalance.add(
                stakingBalance.mul(merchantStakingShares[_user]).div(
                    stakingShares
                )
            );
        }
        return xgtBalance;
    }

    function getUserXDaiBalance(address _user) external view returns (uint256) {
        return customerBalancesBase[_user];
    }

    modifier onlyAuthorized() {
        require(
            authorized[msg.sender] || msg.sender == owner(),
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
            msg.sender == address(subscriptions) ||
                msg.sender == purchases ||
                msg.sender == address(hub),
            "Not authorized"
        );
        _;
    }
}
