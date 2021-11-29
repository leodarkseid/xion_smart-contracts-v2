// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRewardChest.sol";
import "../interfaces/IXGTFreezer.sol";

contract StakingModule_v2 is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using SafeMathUpgradeable for uint256;

    struct UserInfo {
        uint256 stake;
        uint256 lastDepositedTime;
        uint256 lastUserActionTime;
        uint256 debt;
        uint256[] referralIDs;
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
    IERC20[] public rewardTokens;
    IERC20 public stakeToken;
    IXGTFreezer public freezer;
    IRewardChest public rewardChest;

    // Addresses
    address public feeWallet;

    // Authorization & Access
    mapping(address => bool) public authorized;

    // Reward balances
    mapping(address => uint256) public rewardedTokenBalances;
    uint256 public rewardPerStakedToken;
    bool public withdrawRewardsOnHarvest;

    // User Specific Info
    mapping(address => UserInfo) public userInfo;
    mapping(address => mapping(address => uint256)) public userRewards;

    // Tracking Variables
    uint256 public totalStaked;
    uint256 public lastHarvestedTime;

    // Constants
    uint256 public constant YEAR_IN_SECONDS = 31536000;
    uint256 public constant BP_DECIMALS = 10000;

    // Fees and Percentage Values
    uint256 public performanceFee;
    uint256 public harvestReward;
    uint256 public withdrawFee;
    uint256 public withdrawFeePeriod;

    // APY related Variables
    bool public fixedAPYPool;
    APYDetail[] public apyDetails;

    struct APYDetail {
        uint256 apy;
        uint256 priceModifier;
        uint256 calcApy;
    }

    // Time Variables
    uint256 public start;
    uint256 public end;

    // Referral System
    Referral[] public referrals;
    uint256 public referralMinTime;
    uint256 public referralMinAmount;
    mapping(address => uint256) public referralMinAmountSince;

    event Deposit(
        address indexed sender,
        uint256 amount,
        uint256 lastDepositedTime
    );
    event Withdraw(address indexed sender, uint256 amount);
    event Harvest(address indexed sender, uint256 performanceFee);

    function initialize(
        address[] calldata _rewardTokens,
        address _stakeToken,
        address _freezer,
        address _rewardChest,
        bool _fixedAPYPool,
        uint256[] calldata _stakingAPYs,
        uint256 _poolStart,
        uint256 _poolEnd
    ) public initializer {
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            rewardTokens.push(IERC20(_rewardTokens[i]));
        }
        stakeToken = IERC20(_stakeToken);

        xgt = IERC20(0xC25AF3123d2420054c8fcd144c21113aa2853F39);
        if (_freezer != address(0)) {
            freezer = IXGTFreezer(_freezer);
            xgt.approve(_freezer, 2**256 - 1);
        }

        rewardChest = IRewardChest(_rewardChest);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();

        if (_rewardChest != address(0)) {
            transferOwnership(rewardChest.owner());
        }

        fixedAPYPool = _fixedAPYPool;
        for (uint256 j = 0; j < _stakingAPYs.length; j++) {
            apyDetails.push(
                APYDetail(_stakingAPYs[j], 10**18, _stakingAPYs[j].div(10**2))
            );
        }

        if (_poolStart > 0 && _poolEnd > 0) {
            require(
                _poolStart < _poolEnd && _poolEnd > block.timestamp,
                "XGT-REWARD-MODULE-WRONG-DATES"
            );
            start = _poolStart;
            end = _poolEnd;
            lastHarvestedTime = start;
        } else {
            lastHarvestedTime = block.timestamp;
        }

        performanceFee = 200; // 2%
        harvestReward = 25; // 0.25%
        withdrawFee = 10; // 0.1%
        withdrawFeePeriod = 72 hours;
        withdrawRewardsOnHarvest = true;

        referralMinTime = 604800; // 1 week
        referralMinAmount = 100; // 100 stake tokens
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

    function setWithdrawFee(uint256 _withdrawFee) external onlyOwner {
        withdrawFee = _withdrawFee;
    }

    function setWithdrawFeePeriod(uint256 _withdrawFeePeriod)
        external
        onlyOwner
    {
        withdrawFeePeriod = _withdrawFeePeriod;
    }

    function setStakingAPYs(bool _fixedAPYPool, uint256[] calldata _stakingAPYs)
        external
        onlyOwner
    {
        require(
            apyDetails.length == _stakingAPYs.length,
            "XGT-REWARD-MODULE-ARRAY-MISMATCH"
        );
        fixedAPYPool = _fixedAPYPool;
        for (uint256 j = 0; j < apyDetails.length; j++) {
            apyDetails[j].apy = _stakingAPYs[j];
            apyDetails[j].calcApy = apyDetails[j]
                .apy
                .mul(apyDetails[j].priceModifier)
                .div(10**20); // 10^18 * 100 because of the percent value
        }
    }

    function setPriceModifiers(uint256[] calldata _priceModifiers)
        external
        onlyAuthorized
    {
        for (uint256 j = 0; j < apyDetails.length; j++) {
            apyDetails[j].priceModifier = _priceModifiers[j];
            apyDetails[j].calcApy = apyDetails[j]
                .apy
                .mul(apyDetails[j].priceModifier)
                .div(10**20); // 10^18 * 100 because of the percent value
        }
    }

    function extendPool(uint256 _newEndDate) external onlyOwner {
        require(
            _newEndDate >= block.timestamp,
            "XGT-REWARD-MODULE-CANT-EXTEND-INTO-THE-PAST"
        );
        end = _newEndDate;
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            require(
                _token != address(rewardTokens[i]),
                "XGT-REWARD-MODULE-TOKEN-CANT-BE-REWARD-TOKEN"
            );
        }

        require(
            _token != address(stakeToken),
            "XGT-REWARD-MODULE-TOKEN-CANT-BE-REWARD-TOKEN"
        );

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, amount);
    }

    function cleanUp() external onlyOwner {
        if (block.timestamp > end) {
            // this will withdraw any reward tokens that have not been
            // allocated for rewards
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                uint256 rewardRemainder = balanceOfRewardToken(
                    address(rewardTokens[i])
                ).sub(rewardedTokenBalances[address(rewardTokens[i])]);
                if (rewardRemainder > 0) {
                    rewardTokens[i].transfer(msg.sender, rewardRemainder);
                }
            }
        }
        // This will only withdraw any exess staked tokens (accidental sends etc.)
        uint256 stakeRemainder = balanceOf().sub(totalStaked);
        if (stakeRemainder > 0) {
            stakeToken.transfer(msg.sender, stakeRemainder);
        }
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
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
        require(
            block.timestamp >= start && block.timestamp < end,
            "XGT-REWARD-MODULE-POOL-NOT-OPEN"
        );
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

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 rewardTilNow = _getUserReward(_user, i);

            userRewards[_user][address(rewardTokens[i])] = userRewards[_user][
                address(rewardTokens[i])
            ].add(rewardTilNow);
        }

        user.stake = user.stake.add(_amount);
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
        user.debt = user.stake.mul(rewardPerStakedToken).div(10**18);
        user.lastUserActionTime = block.timestamp;
        if (!_skipLastDepositUpdate) {
            user.lastDepositedTime = block.timestamp;
        }

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

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 amount = _getUserReward(_user, i);
            if (userRewards[_user][address(rewardTokens[i])] > 0) {
                amount = amount.add(
                    userRewards[_user][address(rewardTokens[i])]
                );
                userRewards[_user][address(rewardTokens[i])] = 0;
            }
            rewardedTokenBalances[
                address(rewardTokens[i])
            ] = rewardedTokenBalances[address(rewardTokens[i])].sub(amount);

            rewardTokens[i].transfer(_user, amount);
        }

        uint256 withdrawAmount = _withdrawAmount;
        user.stake = user.stake.sub(withdrawAmount);
        totalStaked = totalStaked.sub(withdrawAmount);
        user.debt = user.stake.mul(rewardPerStakedToken).div(10**18);

        if (
            user.stake < referralMinAmount && referralMinAmountSince[_user] != 0
        ) {
            referralMinAmountSince[_user] = 0;
        }

        user.lastUserActionTime = block.timestamp;

        if (withdrawAmount > 0) {
            if (
                block.timestamp < user.lastDepositedTime.add(withdrawFeePeriod)
            ) {
                uint256 currentWithdrawFee = withdrawAmount
                    .mul(withdrawFee)
                    .div(BP_DECIMALS);
                if (stakeToken == xgt) {
                    freezer.freeze(currentWithdrawFee);
                } else if (feeWallet != address(0)) {
                    stakeToken.transfer(feeWallet, currentWithdrawFee);
                }
                withdrawAmount = withdrawAmount.sub(currentWithdrawFee);
            }

            stakeToken.transfer(_user, withdrawAmount);

            emit Withdraw(_user, withdrawAmount);
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
            uint256 baseHarvestAmount = _getHarvestAmount(diff);
            if (baseHarvestAmount == 0) return;
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                uint256 harvestAmount = baseHarvestAmount
                    .mul(apyDetails[i].calcApy)
                    .div(apyDetails[0].calcApy);

                if (rewardTokens[i] == xgt) {
                    require(
                        rewardChest.sendInstantClaim(
                            address(this),
                            harvestAmount
                        ),
                        "XGT-REWARD-MODULE-INSTANT-CLAIM-FROM-CHEST-FAILED"
                    );
                }

                uint256 currentPerformanceFee = harvestAmount
                    .mul(performanceFee)
                    .div(BP_DECIMALS);
                if (rewardTokens[i] == xgt) {
                    freezer.freeze(currentPerformanceFee);
                } else if (feeWallet != address(0)) {
                    IERC20(address(rewardTokens[i])).transfer(
                        feeWallet,
                        currentPerformanceFee
                    );
                }

                uint256 currentHarvestReward = harvestAmount
                    .mul(harvestReward)
                    .div(BP_DECIMALS);
                if (_storeHarvestReward) {
                    userRewards[msg.sender][
                        address(rewardTokens[i])
                    ] = userRewards[msg.sender][address(rewardTokens[i])].add(
                        currentHarvestReward
                    );

                    rewardedTokenBalances[
                        address(rewardTokens[i])
                    ] = rewardedTokenBalances[address(rewardTokens[i])].add(
                        (currentHarvestReward)
                    );
                } else {
                    IERC20(address(rewardTokens[i])).transfer(
                        msg.sender,
                        currentHarvestReward
                    );
                }

                uint256 netHarvest = harvestAmount
                    .sub(currentPerformanceFee)
                    .sub(currentHarvestReward);

                rewardedTokenBalances[
                    address(rewardTokens[i])
                ] = rewardedTokenBalances[address(rewardTokens[i])].add(
                    (netHarvest)
                );

                if (i == 0) {
                    if (totalStaked > 0) {
                        rewardPerStakedToken = rewardPerStakedToken.add(
                            netHarvest.mul(10**18).div(totalStaked)
                        );
                    } else {
                        rewardPerStakedToken = 0;
                    }
                }

                require(
                    balanceOfRewardToken(address(rewardTokens[i])) >=
                        rewardedTokenBalances[address(rewardTokens[i])],
                    "XGT-REWARD-MODULE-NOT-ENOUGH-REWARDS"
                );

                emit Harvest(msg.sender, currentPerformanceFee);
            }
            lastHarvestedTime = harvestTime;
        }
    }

    function currentHarvestAmount(uint256 _rewardTokenIndex)
        public
        view
        returns (uint256)
    {
        (uint256 diff, ) = _getHarvestDiffAndTime();
        uint256 harvestAmount = _getHarvestAmount(diff);
        harvestAmount = harvestAmount
            .mul(apyDetails[_rewardTokenIndex].calcApy)
            .div(apyDetails[0].calcApy);
        return harvestAmount;
    }

    function _getHarvestAmount(uint256 _diff) internal view returns (uint256) {
        uint256 harvestAmount = 0;
        if (fixedAPYPool) {
            // for fixed pools the calcApy variable
            // contains a percentage-like value
            // to ensure a fixed amount of rewards
            harvestAmount = totalStaked
                .mul(apyDetails[0].calcApy)
                .mul(_diff)
                .div(YEAR_IN_SECONDS)
                .div(10**18);
        } else {
            // for dynamic pools, the calcApy variable
            // contains the token amount rewarded to the
            // pool for each second
            // so it is high for low participation
            // and low for high participation
            if (totalStaked > 0) {
                harvestAmount = apyDetails[0].calcApy.mul(_diff);
            }
        }
        return harvestAmount;
    }

    function _getHarvestDiffAndTime() internal view returns (uint256, uint256) {
        uint256 until = block.timestamp;
        if (until > end) {
            until = end;
        }
        return (until.sub(lastHarvestedTime), until);
    }

    function getCurrentUserReward(address _user, uint256 _rewardTokenIndex)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_user];
        uint256 newHarvestAmount = currentHarvestAmount(_rewardTokenIndex);
        newHarvestAmount = newHarvestAmount.sub(
            newHarvestAmount.mul(
                (performanceFee.add(harvestReward)).div(BP_DECIMALS)
            )
        );

        uint256 newRewardPerStakedToken = rewardPerStakedToken.add(
            newHarvestAmount.mul(10**18).div(totalStaked)
        );

        uint256 reward = (
            (user.stake.mul(newRewardPerStakedToken).div(10**18)).sub(user.debt)
        ).mul(apyDetails[_rewardTokenIndex].calcApy).div(apyDetails[0].calcApy);

        reward = reward.add(
            userRewards[_user][address(rewardTokens[_rewardTokenIndex])]
        );

        return reward;
    }

    function _getUserReward(address _user, uint256 _rewardTokenIndex)
        internal
        view
        returns (uint256)
    {
        return
            (
                (userInfo[_user].stake.mul(rewardPerStakedToken).div(10**18))
                    .sub(userInfo[_user].debt)
            ).mul(apyDetails[_rewardTokenIndex].calcApy).div(
                    apyDetails[0].calcApy
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
