// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRewardChest.sol";
import "../interfaces/IXGTFreezer.sol";

contract StakingModule is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using SafeMathUpgradeable for uint256;

    struct UserInfo {
        uint256 shares;
        uint256 deposits;
        uint256 lastDepositedTime;
        uint256 lastUserActionTime;
    }

    IERC20 public xgt;
    IXGTFreezer public freezer;
    IRewardChest public rewardChest;

    mapping(address => bool) public authorized;
    mapping(address => UserInfo) public userInfo;

    uint256 public totalShares;
    uint256 public lastHarvestedTime;
    uint256 public autoHarvestAfter;

    uint256 public constant YEAR_IN_SECONDS = 31536000;
    uint256 public constant BP_DECIMALS = 10000;

    uint256 public performanceFee;
    uint256 public callFee;
    uint256 public withdrawFee;
    uint256 public withdrawFeePeriod;
    uint256 public stakingAPY;

    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 shares,
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount, uint256 shares);
    event Harvest(
        address indexed sender,
        uint256 performanceFee,
        uint256 callFee
    );

    function initialize(
        address _xgt,
        address _freezer,
        address _rewardChest
    ) public initializer {
        xgt = IERC20(_xgt);
        freezer = IXGTFreezer(_freezer);
        xgt.approve(_freezer, 2**256 - 1);
        rewardChest = IRewardChest(_rewardChest);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(rewardChest.owner());

        performanceFee = 200; // 2%
        callFee = 25; // 0.25%
        withdrawFee = 10; // 0.1%
        withdrawFeePeriod = 72 hours;
        stakingAPY = 9500; // 95% base APY, with compounding effect this is 150%
        autoHarvestAfter = 1 hours;
    }

    function setAuthorized(address _addr, bool _authorized) external onlyOwner {
        authorized[_addr] = _authorized;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        performanceFee = _performanceFee;
    }

    function setCallFee(uint256 _callFee) external onlyOwner {
        callFee = _callFee;
    }

    function setWithdrawFee(uint256 _withdrawFee) external onlyOwner {
        withdrawFee = _withdrawFee;
    }

    function setWithdrawFeePeriod(uint256 _withdrawFeePeriod)
        external
        onlyOwner
    {
        withdrawFeePeriod = _withdrawFeePeriod;
    }

    function setStakingAPY(uint256 _stakingAPY) external onlyOwner {
        stakingAPY = _stakingAPY;
    }

    function setAutoHarvestTime(uint256 _autoHarvestTime) external onlyOwner {
        autoHarvestAfter = _autoHarvestTime;
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(xgt), "XGT-REWARD-MODULE-TOKEN-CANT-BE-XGT");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function deposit(uint256 _amount) external whenNotPaused notContract {
        uint256 harvestReward = autoHarvestIfNecessary();
        _deposit(msg.sender, _amount, harvestReward, false);
    }

    function depositForUser(
        address _user,
        uint256 _amount,
        bool _skipLastDepositUpdate
    ) external whenNotPaused onlyAuthorized {
        _deposit(_user, _amount, 0, _skipLastDepositUpdate);
    }

    function _deposit(
        address _user,
        uint256 _amount,
        uint256 _harvestReward,
        bool _skipLastDepositUpdate
    ) internal {
        require(_amount > 0, "XGT-REWARD-MODULE-CANT-DEPOSIT-ZERO");
        uint256 totalAmount = _amount.add(_harvestReward);
        uint256 currentShares = 0;
        uint256 currentBalance = balanceOf();
        xgt.transferFrom(_user, address(this), _amount);
        if (totalShares != 0) {
            currentShares = (totalAmount.mul(totalShares)).div(currentBalance);
        } else {
            currentShares = totalAmount;
        }
        UserInfo storage user = userInfo[_user];

        user.shares = user.shares.add(currentShares);
        user.deposits = user.deposits.add(totalAmount);
        totalShares = totalShares.add(currentShares);
        user.lastUserActionTime = block.timestamp;
        if (_skipLastDepositUpdate) {
            user.lastDepositedTime = block.timestamp;
        }

        emit Deposit(_user, totalAmount, currentShares, block.timestamp);
    }

    function withdraw(uint256 _shares) external notContract {
        uint256 harvestReward = autoHarvestIfNecessary();
        _withdraw(msg.sender, _shares, harvestReward);
    }

    function withdrawForUser(address _user, uint256 _shares)
        external
        onlyAuthorized
    {
        _withdraw(_user, _shares, 0);
    }

    function withdrawAll() external notContract {
        uint256 harvestReward = autoHarvestIfNecessary();
        _withdraw(msg.sender, userInfo[msg.sender].shares, harvestReward);
    }

    function withdrawAllForUser(address _user) external onlyAuthorized {
        _withdraw(_user, userInfo[_user].shares, 0);
    }

    function _withdraw(
        address _user,
        uint256 _shares,
        uint256 _harvestReward
    ) internal {
        UserInfo storage user = userInfo[_user];
        require(
            _shares > 0,
            "XGT-REWARD-MODULE-NEED-TO-WITHDRAW-MORE-THAN-ZERO"
        );
        require(
            _shares <= user.shares,
            "XGT-REWARD-MODULE-CANT-WITHDRAW-MORE-THAN-MAXIMUM"
        );
        // subtract hardvest reward from balance, since it's not part
        // of the current balance originally
        uint256 currentAmount = ((balanceOf().sub(_harvestReward)).mul(_shares))
            .div(totalShares);
        user.shares = user.shares.sub(_shares);
        totalShares = totalShares.sub(_shares);
        user.deposits = user.deposits.mul(user.shares).div(
            (user.shares.add(_shares))
        );

        if (block.timestamp < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 currentWithdrawFee = currentAmount.mul(withdrawFee).div(
                BP_DECIMALS
            );
            freezer.freeze(currentWithdrawFee);
            currentAmount = currentAmount.sub(currentWithdrawFee);
        }

        user.lastUserActionTime = block.timestamp;
        currentAmount = currentAmount.add(_harvestReward);
        xgt.transfer(_user, currentAmount);

        emit Withdraw(_user, currentAmount, _shares);
    }

    function harvest() public notContract whenNotPaused {
        _harvest(false);
    }

    function autoHarvestIfNecessary() public returns (uint256) {
        uint256 gainedReward = 0;
        if (block.timestamp.sub(lastHarvestedTime) > autoHarvestAfter) {
            gainedReward = _harvest(true);
        }
        return gainedReward;
    }

    function _harvest(bool _autoHarvest) internal returns (uint256) {
        uint256 harvestAmount = currentHarvestAmount();
        require(
            rewardChest.sendInstantClaim(address(this), harvestAmount),
            "XGT-REWARD-MODULE-INSTANT-CLAIM-FROM-CHEST-FAILED"
        );

        uint256 currentPerformanceFee = harvestAmount.mul(performanceFee).div(
            BP_DECIMALS
        );
        freezer.freeze(currentPerformanceFee);

        uint256 currentCallFee = harvestAmount.mul(callFee).div(BP_DECIMALS);

        // If it's an auto-harvest, it stays in the pool and
        // the user gets the amount added to their deposit amount,
        // immediately reinvesting this amount for the user
        if (!_autoHarvest) {
            xgt.transfer(msg.sender, currentCallFee);
        }

        lastHarvestedTime = block.timestamp;

        emit Harvest(msg.sender, currentPerformanceFee, currentCallFee);
        return currentCallFee;
    }

    function currentHarvestAmount() public view returns (uint256) {
        uint256 diff = block.timestamp.sub(lastHarvestedTime);
        uint256 harvestAmount = balanceOf()
            .mul(stakingAPY)
            .mul(diff)
            .div(BP_DECIMALS)
            .div(YEAR_IN_SECONDS);
        return harvestAmount;
    }

    function getCurrentUserBalance(address _user)
        public
        view
        returns (uint256)
    {
        uint256 harvestAfterFees = currentHarvestAmount()
            .mul(BP_DECIMALS.sub(performanceFee).sub(callFee))
            .div(BP_DECIMALS);
        uint256 balanceAfterHarvest = balanceOf().add(harvestAfterFees);
        if (totalShares == 0) {
            return 0;
        }
        return balanceAfterHarvest.mul(userInfo[_user].shares).div(totalShares);
    }

    function getCurrentUserInfo(address _user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            getCurrentUserBalance(_user),
            userInfo[_user].deposits,
            userInfo[_user].shares
        );
    }

    function balanceOf() public view returns (uint256) {
        return xgt.balanceOf(address(this));
    }

    function getHarvestRewards() external view returns (uint256) {
        uint256 amount = currentHarvestAmount();
        uint256 currentCallFee = amount.mul(callFee).div(BP_DECIMALS);

        return currentCallFee;
    }

    function getPricePerFullShare() external view returns (uint256) {
        return totalShares == 0 ? 1e18 : balanceOf().mul(1e18).div(totalShares);
    }

    // Only for compatibility with reward chest
    function claimModule(address _user) external pure {
        return;
    }

    // Only for compatibility with reward chest
    function getClaimable(address _user) external pure returns (uint256) {
        return 0;
    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    modifier notContract() {
        require(
            !_isContract(msg.sender),
            "XGT-REWARD-MODULE-NO-CONTRACTS-ALLOWED"
        );
        require(
            msg.sender == tx.origin,
            "XGT-REWARD-MODULE-PROXY-CONTRACT-NOT-ALLOWED"
        );
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorized[msg.sender],
            "XGT-REWARD-MODULE-CALLER-NOT-AUTHORIZED"
        );
        _;
    }
}
