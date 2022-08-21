// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRewardChest.sol";
import "../interfaces/IXGTFreezer.sol";

contract StakingModule_IDO is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using SafeMathUpgradeable for uint256;

    struct UserInfo {
        uint256 stake;
        uint256 eligibleStake;
        uint256 lastDepositedTime;
        uint256 lastUserActionTime;
        uint256 debt;
        uint256[] referralIDs;
        uint256 lastLock;
    }

    struct Referral {
        address referring;
        address referral;
        uint256 date;
        bool counted;
        bool rewarded;
    }

    // Tokens & Contracts
    IERC20 public xgt;
    IERC20 public stakeToken;
    IXGTFreezer public freezer;
    IRewardChest public rewardChest;
    address public mainPool;

    // Addresses
    address public feeWallet;

    // Authorization & Access
    mapping(address => bool) public authorized;

    // Reward balances
    uint256 public rewardedTokenBalance;
    uint256 public rewardPerStakedToken;
    bool public withdrawRewardsOnHarvest;

    // User Specific Info
    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public userRewards;

    // Tracking Variables
    uint256 public totalStaked;
    uint256 public lastHarvestedTime;

    // Constants
    uint256 public constant YEAR_IN_SECONDS = 31536000;
    uint256 public constant BP_DECIMALS = 10000;

    // Fees and Percentage Values
    uint256 public performanceFee;
    uint256 public harvestReward;

    // APY related Variables
    uint256 public apy;

    // Time Variables
    uint256 public lastUnlock;
    uint256 public nextCutOff;
    uint256 public nextUnlock;

    // Referral System
    Referral[] public referrals;
    uint256 public referralMinTime;
    uint256 public referralMinAmount;
    mapping(address => uint256) public referralMinAmountSince;

    // Locking System
    bool public autoLock;

    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount);
    event Harvest(address indexed sender, uint256 performanceFee);

    function initialize(
        address _stakeToken,
        address _freezer,
        address _rewardChest,
        address _mainPool,
        uint256 _apy,
        bool _autoLock
    ) public initializer {
        stakeToken = IERC20(_stakeToken);

        xgt = IERC20(0xC25AF3123d2420054c8fcd144c21113aa2853F39);
        if (_freezer != address(0)) {
            freezer = IXGTFreezer(_freezer);
            xgt.approve(_freezer, 2**256 - 1);
        }

        rewardChest = IRewardChest(_rewardChest);
        mainPool = _mainPool;
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();

        // if (_rewardChest != address(0)) {
        //     transferOwnership(rewardChest.owner());
        // }

        apy = _apy;

        lastHarvestedTime = block.timestamp;

        autoLock = _autoLock;

        performanceFee = 200; // 2%
        harvestReward = 25; // 0.25%

        referralMinTime = 604800; // 1 week
        referralMinAmount = 100; // 100 stake tokens

        // initial values
        withdrawRewardsOnHarvest = true;
        feeWallet = 0xc13103AEe15ca9D4814F4Fc436cdD3a57Dd50587;
    }

    function setAuthorized(address _addr, bool _authorized) external onlyOwner {
        authorized[_addr] = _authorized;
    }

    function setWithdrawRewardsOnHarvest(bool _withdrawRewardsOnHarvest)
        external
        onlyOwner
    {
        withdrawRewardsOnHarvest = _withdrawRewardsOnHarvest;
    }

    function setReferralVariables(uint256 _minTime, uint256 _minAmount)
        external
        onlyOwner
    {
        referralMinTime = _minTime;
        referralMinAmount = _minAmount;
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        performanceFee = _performanceFee;
    }

    function setStakingAPY(uint256 _apy) external onlyOwner {
        apy = _apy;
    }

    function setAutoLock(bool _active) external onlyOwner {
        autoLock = _active;
    }

    function changeNextDates(
        uint256 _newCutoffDate,
        uint256 _newUnlockDate,
        bool _correction
    ) external onlyOwner {
        if (!_correction) {
            lastUnlock = nextUnlock;
        }
        nextCutOff = _newCutoffDate;
        nextUnlock = _newUnlockDate;
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(
            _token != address(stakeToken) && _token != address(xgt),
            "XGT-REWARD-MODULE-TOKEN-CANT-BE-REWARD-OR-STAKE-TOKEN"
        );

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function lock() external whenNotPaused notContract {
        require(
            block.timestamp <= nextCutOff ||
                (block.timestamp >= nextUnlock && nextUnlock != 0),
            "XGT-REWARD-MODULE-CANT-LOCK-DURING-LOCKED-PERIOD"
        );
        userInfo[msg.sender].lastLock = block.timestamp;
    }

    function userIsLocked(address _user) public view returns (bool) {
        if (nextUnlock == 0) {
            return false;
        }

        if (autoLock) {
            if (
                block.timestamp > nextCutOff.sub(2 days) &&
                block.timestamp < nextUnlock
            ) {
                return true;
            }
        } else {
            uint256 lastLockTime = userInfo[_user].lastLock;
            if (lastLockTime == 0) {
                return false;
            }
            // if user locked pre cutoff, they are in
            if (lastLockTime <= nextCutOff) {
                return true;
            }
        }
        return false;
    }

    function deposit(uint256 _amount, address _referrer)
        external
        whenNotPaused
        notContract
    {
        _deposit(msg.sender, _referrer, _amount, false);
    }

    function depositForUser(
        address _user,
        uint256 _amount,
        bool _skipLastDepositUpdate
    ) external whenNotPaused onlyAuthorized {
        _deposit(_user, address(0), _amount, _skipLastDepositUpdate);
    }

    function _deposit(
        address _user,
        address _referrer,
        uint256 _amount,
        bool _skipLastDepositUpdate
    ) internal {
        _harvest(true);
        require(_amount > 0, "XGT-REWARD-MODULE-CANT-DEPOSIT-ZERO");

        stakeToken.transferFrom(_user, address(this), _amount);

        UserInfo storage user = userInfo[_user];

        if (
            _referrer != address(0) &&
            user.lastUserActionTime == 0 &&
            userInfo[_referrer].stake > referralMinAmount
        ) {
            Referral memory newRef = Referral(
                _referrer,
                _user,
                block.timestamp,
                false,
                false
            );
            referrals.push(newRef);
            // add the index/id of the referral to both of the users referral id array
            user.referralIDs.push(referrals.length - 1);
            userInfo[_referrer].referralIDs.push(referrals.length - 1);
        }

        uint256 rewardTilNow = _getUserReward(_user);

        userRewards[_user] = userRewards[_user].add(rewardTilNow);

        user.stake = user.stake.add(_amount);

        // if the user deposists during a locked period,
        // the code below will not include the users added
        // tokens to the eligible amount
        // if the deposit happens before or after the locked period,
        // it is included
        // if the values are still set to 0 (fresh pool)
        // the first expression is true so it executes.
        // the function getUserEligibleStakeInXGT() does include
        // the regular stake, if the users last deposit happend
        // before this IDO locking round, which we track via the
        // lastDepositedTime variable.
        if (nextUnlock <= block.timestamp || block.timestamp < nextCutOff) {
            user.eligibleStake = user.stake;
        }

        if (
            user.stake >= referralMinAmount &&
            referralMinAmountSince[_user] == 0
        ) {
            referralMinAmountSince[_user] = block.timestamp;
        }

        if (totalStaked == 0) {
            lastHarvestedTime = block.timestamp;
        }
        totalStaked = totalStaked.add(_amount);
        user.debt = user.stake.mul(rewardPerStakedToken).div(1e18);
        user.lastUserActionTime = block.timestamp;
        if (!_skipLastDepositUpdate) {
            user.lastDepositedTime = block.timestamp;
        }

        address(0x46C1B22922CCc62F39419147381f1efbb2aE2a68).call(
            abi.encodeWithSignature(
                "update(address,uint256)",
                _user,
                user.stake
            )
        );

        emit Deposit(_user, _amount, block.timestamp);
    }

    function withdraw(uint256 _shares) external notContract {
        _withdraw(msg.sender, _shares);
    }

    function withdrawForUser(address _user, uint256 _shares)
        external
        onlyAuthorized
    {
        _withdraw(_user, _shares);
    }

    function withdrawAll() external notContract {
        _withdraw(msg.sender, userInfo[msg.sender].stake);
    }

    function withdrawAllForUser(address _user) external onlyAuthorized {
        _withdraw(_user, userInfo[_user].stake);
    }

    function _withdraw(address _user, uint256 _withdrawAmount) internal {
        // harvest so the rewards are up to date for the withdraw
        _harvest(true);

        // check all referrals of the user on whether they are due/matured
        _countDueReferrals(_user);

        UserInfo storage user = userInfo[_user];
        require(
            _withdrawAmount <= user.stake,
            "XGT-REWARD-MODULE-CANT-WITHDRAW-MORE-THAN-MAXIMUM"
        );

        require(
            !userIsLocked(_user) || _withdrawAmount == 0,
            "XGT-REWARD-MODULE-CANT-WITHDRAW-WHEN-LOCKED"
        );

        uint256 amount = _getUserReward(_user);
        if (userRewards[_user] > 0) {
            amount = amount.add(userRewards[_user]);
            userRewards[_user] = 0;
        }
        rewardedTokenBalance = rewardedTokenBalance.sub(amount);

        xgt.transfer(_user, amount);

        user.stake = user.stake.sub(_withdrawAmount);
        if (user.eligibleStake > user.stake) {
            user.eligibleStake = user.stake;
        }

        totalStaked = totalStaked.sub(_withdrawAmount);
        user.debt = user.stake.mul(rewardPerStakedToken).div(1e18);

        if (
            user.stake < referralMinAmount && referralMinAmountSince[_user] != 0
        ) {
            referralMinAmountSince[_user] = 0;
        }

        user.lastUserActionTime = block.timestamp;

        address(0x46C1B22922CCc62F39419147381f1efbb2aE2a68).call(
            abi.encodeWithSignature(
                "update(address,uint256)",
                _user,
                user.stake
            )
        );

        if (_withdrawAmount > 0) {
            stakeToken.transfer(_user, _withdrawAmount);

            emit Withdraw(_user, _withdrawAmount);
        }
    }

    function harvest() public whenNotPaused {
        if (userInfo[msg.sender].stake > 0) {
            _harvest(true);
            if (withdrawRewardsOnHarvest) {
                _withdraw(msg.sender, 0); // withdrawing 0 is equal to withdrawing just the rewards
            }
        } else {
            _harvest(false);
        }
    }

    function _harvest(bool _storeHarvestReward) internal {
        if (lastHarvestedTime < block.timestamp) {
            (uint256 diff, uint256 harvestTime) = _getHarvestDiffAndTime();
            uint256 harvestAmount = _getHarvestAmount(diff);

            require(
                rewardChest.sendInstantClaim(address(this), harvestAmount),
                "XGT-REWARD-MODULE-INSTANT-CLAIM-FROM-CHEST-FAILED"
            );

            uint256 currentPerformanceFee = 0;
            if (address(freezer) != address(0)) {
                currentPerformanceFee = harvestAmount.mul(performanceFee).div(
                    BP_DECIMALS
                );
                freezer.freeze(currentPerformanceFee);
            }

            uint256 currentHarvestReward = harvestAmount.mul(harvestReward).div(
                BP_DECIMALS
            );
            if (_storeHarvestReward) {
                userRewards[msg.sender] = userRewards[msg.sender].add(
                    currentHarvestReward
                );

                rewardedTokenBalance = rewardedTokenBalance.add(
                    (currentHarvestReward)
                );
            } else {
                xgt.transfer(msg.sender, currentHarvestReward);
            }

            uint256 netHarvest = harvestAmount.sub(currentPerformanceFee).sub(
                currentHarvestReward
            );

            rewardedTokenBalance = rewardedTokenBalance.add((netHarvest));

            if (totalStaked > 0) {
                rewardPerStakedToken = rewardPerStakedToken.add(
                    netHarvest.mul(1e18).div(totalStaked)
                );
            } else {
                rewardPerStakedToken = 0;
            }

            require(
                balanceOfRewardToken(address(xgt)) >= rewardedTokenBalance,
                "XGT-REWARD-MODULE-NOT-ENOUGH-REWARDS"
            );

            emit Harvest(msg.sender, currentPerformanceFee);

            lastHarvestedTime = harvestTime;
        }
    }

    function currentHarvestAmount() public view returns (uint256) {
        (uint256 diff, ) = _getHarvestDiffAndTime();
        uint256 harvestAmount = _getHarvestAmount(diff);
        return harvestAmount;
    }

    function _getHarvestAmount(uint256 _diff) internal view returns (uint256) {
        uint256 harvestAmount = totalStaked
            .mul(getXGTperStakedToken())
            .mul(apy)
            .mul(_diff)
            .div(YEAR_IN_SECONDS)
            .div(1e24);

        return harvestAmount;
    }

    function _getHarvestDiffAndTime() internal view returns (uint256, uint256) {
        uint256 until = block.timestamp;

        return (until.sub(lastHarvestedTime), until);
    }

    function getCurrentUserReward(address _user)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];
        uint256 newHarvestAmount = currentHarvestAmount();
        newHarvestAmount = newHarvestAmount.sub(
            newHarvestAmount.mul(
                (performanceFee.add(harvestReward)).div(BP_DECIMALS)
            )
        );

        uint256 newRewardPerStakedToken = rewardPerStakedToken.add(
            newHarvestAmount.mul(1e18).div(totalStaked)
        );

        uint256 reward = (
            (user.stake.mul(newRewardPerStakedToken).div(1e18)).sub(user.debt)
        );

        reward = reward.add(userRewards[_user]);

        return reward;
    }

    function _getUserReward(address _user) internal view returns (uint256) {
        return (
            (userInfo[_user].stake.mul(rewardPerStakedToken).div(1e18)).sub(
                userInfo[_user].debt
            )
        );
    }

    function balanceOf() public view returns (uint256) {
        return stakeToken.balanceOf(address(this));
    }

    function balanceOfRewardToken(address _rewardToken)
        public
        view
        returns (uint256)
    {
        return IERC20(_rewardToken).balanceOf(address(this));
    }

    function redeemReferrals(address _user)
        external
        onlyRewardChest
        returns (uint256 redeemedOfReferrals)
    {
        for (uint256 i = 0; i < userInfo[_user].referralIDs.length; i++) {
            (bool foundDue, ) = _checkReferral(
                referrals[userInfo[_user].referralIDs[i]],
                _user
            );
            if (foundDue) {
                referrals[userInfo[_user].referralIDs[i]].rewarded = true;
                redeemedOfReferrals++;
            }
        }
    }

    function userHasDueReferral(address _user) external view returns (bool) {
        for (uint256 i = 0; i < userInfo[_user].referralIDs.length; i++) {
            (bool foundDue, ) = _checkReferral(
                referrals[userInfo[_user].referralIDs[i]],
                _user
            );
            if (foundDue) {
                return true;
            }
        }
        return false;
    }

    function _countDueReferrals(address _user) internal {
        for (uint256 i = 0; i < userInfo[_user].referralIDs.length; i++) {
            (bool foundDue, bool counted) = _checkReferral(
                referrals[userInfo[_user].referralIDs[i]],
                _user
            );
            if (foundDue && !counted) {
                referrals[userInfo[_user].referralIDs[i]].counted = true;
            }
        }
    }

    function _checkReferral(Referral storage referral, address _user)
        internal
        view
        returns (bool, bool)
    {
        if (
            (referral.referring == _user && // referring user was/is the user
                !referral.rewarded && // the referral has not been rewarded yet
                referral.counted) || // the referral has either been counted already
            (referralMinAmountSince[_user] >= referralMinTime && // or: the referring user did the min time &
                referralMinAmountSince[referral.referral] >= // the referred user did the min time
                referralMinTime)
        ) {
            return (true, referral.counted);
        }
        return (false, false);
    }

    function getUserEligibleStakeInXGT(address _user)
        external
        view
        returns (uint256)
    {
        uint256 eligibleStake = userInfo[_user].eligibleStake;
        uint256 stake = userInfo[_user].stake;
        // IF next unlock is in the past (state after current IDO is over)
        // OR (next unlock is in the future) user has staked during an IDO,
        // but the deposit happened before the current cut off date
        if (
            nextUnlock <= block.timestamp ||
            (eligibleStake != stake &&
                userInfo[_user].lastDepositedTime < nextCutOff)
        ) {
            eligibleStake = stake;
        }

        return (eligibleStake.mul(getXGTperStakedToken())).div(1e18);
    }

    function getXGTperStakedToken() public view returns (uint256) {
        if (address(stakeToken) == address(xgt)) {
            return 1e18;
        }
        if (address(stakeToken) == mainPool) {
            // total xgt in the pool
            uint256 xgtInPool = xgt.balanceOf(mainPool);
            // total lp tokens of that pool
            uint256 totalLPs = IERC20(mainPool).totalSupply();
            // returns: xgt per lp token (1e18)
            return (xgtInPool.mul(2e18)).div(totalLPs);
        }
        return 0;
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

    modifier onlyRewardChest() {
        require(
            msg.sender == address(rewardChest),
            "XGT-REWARD-CHEST-NOT-AUTHORIZED"
        );
        _;
    }
}
