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
        uint256 stake;
        uint256 lastDepositedTime;
        uint256 lastUserActionTime;
        uint256 debt;
        address referrer;
    }

    struct Referral {
        address referring;
        address referral;
        uint256 date;
        bool rewarded;
    }

    IERC20 public xgt;
    IERC20[] public rewardTokens;
    mapping(address => uint256) public rewardedTokenBalances;
    uint256 public rewardPerStakedToken;

    IERC20 public stakeToken;

    IXGTFreezer public freezer;
    address public feeWallet;
    IRewardChest public rewardChest;

    mapping(address => bool) public authorized;

    mapping(address => UserInfo) public userInfo;
    mapping(address => Referral[]) public referrals;
    mapping(address => mapping(address => uint256)) public userCallRewards;

    uint256 public totalStaked;
    uint256 public lastHarvestedTime;

    uint256 public constant YEAR_IN_SECONDS = 31536000;
    uint256 public constant BP_DECIMALS = 10000;

    uint256 public performanceFee;
    uint256 public callFee;
    uint256 public withdrawFee;
    uint256 public withdrawFeePeriod;

    bool public fixedAPYPool;
    uint256[] public stakingAPYs;
    uint256[] public apyRatio;
    uint256 public apyLimitAmount;

    uint256 public start;
    uint256 public end;

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
        uint256 _apyLimitAmount,
        uint256 _poolStart,
        uint256 _poolEnd
    ) public initializer {
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            rewardTokens.push(IERC20(_rewardTokens[i]));
        }
        stakeToken = IERC20(_stakeToken);

        freezer = IXGTFreezer(_freezer);
        xgt = IERC20(0xC25AF3123d2420054c8fcd144c21113aa2853F39);
        xgt.approve(_freezer, 2**256 - 1);

        rewardChest = IRewardChest(_rewardChest);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(rewardChest.owner());

        fixedAPYPool = _fixedAPYPool;
        for (uint256 j = 0; j < _stakingAPYs.length; j++) {
            stakingAPYs.push(_stakingAPYs[j]);
            if (j == 0) {
                apyRatio.push(1 * BP_DECIMALS);
            } else {
                apyRatio.push(
                    _stakingAPYs[j].mul(BP_DECIMALS).div(_stakingAPYs[0])
                );
            }
        }
        if (fixedAPYPool) {
            apyLimitAmount = _apyLimitAmount;
        }

        if (_poolStart > 0 && _poolEnd > 0) {
            require(
                _poolStart < _poolEnd && _poolEnd < block.timestamp,
                "XGT-REWARD-MODULE-WRONG-DATES"
            );
            start = _poolStart;
            end = _poolEnd;
        }

        performanceFee = 200; // 2%
        callFee = 25; // 0.25%
        withdrawFee = 10; // 0.1%
        withdrawFeePeriod = 72 hours;
    }

    function setAuthorized(address _addr, bool _authorized) external onlyOwner {
        authorized[_addr] = _authorized;
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

    function setStakingAPYs(uint256[] calldata _stakingAPYs)
        external
        onlyOwner
    {
        require(
            stakingAPYs.length == _stakingAPYs.length,
            "XGT-REWARD-MODULE-ARRAY-MISMATCH"
        );
        for (uint256 j = 0; j < _stakingAPYs.length; j++) {
            stakingAPYs[j] = _stakingAPYs[j];
            if (j == 0) {
                apyRatio[0] = 1 * BP_DECIMALS;
            } else {
                apyRatio[j] = _stakingAPYs[j].mul(BP_DECIMALS).div(
                    _stakingAPYs[0]
                );
            }
        }
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
                false
            );
            referrals[_user].push(newRef);
            referrals[_referrer].push(newRef);
        }

        user.stake = user.stake.add(_amount);
        if (
            user.stake >= referralMinAmount &&
            referralMinAmountSince[_user] == 0
        ) {
            referralMinAmountSince[_user] = block.timestamp;
        }
        totalStaked = totalStaked.add(_amount);
        user.debt = user.stake.mul(rewardPerStakedToken).div(10**18);
        user.lastUserActionTime = block.timestamp;
        if (_skipLastDepositUpdate) {
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
        _harvest(false);
        UserInfo storage user = userInfo[_user];
        require(
            _withdrawAmount > 0,
            "XGT-REWARD-MODULE-NEED-TO-WITHDRAW-MORE-THAN-ZERO"
        );
        require(
            _withdrawAmount <= user.stake,
            "XGT-REWARD-MODULE-CANT-WITHDRAW-MORE-THAN-MAXIMUM"
        );

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 amount = (user.stake.mul(rewardPerStakedToken)).sub(
                user.debt
            );
            if (i != 0) {
                amount = amount.mul(BP_DECIMALS).div(apyRatio[i]);
            }
            if (userCallRewards[_user][address(rewardTokens[i])] > 0) {
                amount = amount.add(
                    userCallRewards[_user][address(rewardTokens[i])]
                );
                userCallRewards[_user][address(rewardTokens[i])] = 0;
            }
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

        if (block.timestamp < user.lastDepositedTime.add(withdrawFeePeriod)) {
            uint256 currentWithdrawFee = withdrawAmount.mul(withdrawFee).div(
                BP_DECIMALS
            );
            freezer.freeze(currentWithdrawFee);
            withdrawAmount = withdrawAmount.sub(currentWithdrawFee);
        }

        user.lastUserActionTime = block.timestamp;
        stakeToken.transfer(_user, withdrawAmount);

        emit Withdraw(_user, withdrawAmount);
    }

    function harvest() public whenNotPaused {
        _harvest(false);
    }

    function _harvest(bool _storeCallReward) internal {
        if (lastHarvestedTime < block.timestamp) {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                (
                    uint256 harvestAmount,
                    uint256 harvestTime
                ) = currentHarvestAmount(address(rewardTokens[i]));

                // Update rewards per staked token
                if (i == 0) {
                    rewardPerStakedToken = rewardPerStakedToken.add(
                        harvestAmount.mul(10**18).div(totalStaked)
                    );
                }

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

                uint256 currentCallFee = harvestAmount.mul(callFee).div(
                    BP_DECIMALS
                );
                if (_storeCallReward) {
                    userCallRewards[msg.sender][
                        address(rewardTokens[i])
                    ] = userCallRewards[msg.sender][address(rewardTokens[i])]
                        .add(currentCallFee);
                } else {
                    IERC20(address(rewardTokens[i])).transfer(
                        msg.sender,
                        currentCallFee
                    );
                }

                rewardedTokenBalances[
                    address(rewardTokens[i])
                ] = rewardedTokenBalances[address(rewardTokens[i])].add(
                    (
                        harvestAmount.sub(currentPerformanceFee).sub(
                            currentCallFee
                        )
                    )
                );

                require(
                    balanceOfRewardToken(address(rewardTokens[i])) >=
                        rewardedTokenBalances[address(rewardTokens[i])],
                    "XGT-REWARD-MODULE-NOT-ENOUGH-REWARDS"
                );

                lastHarvestedTime = harvestTime;
                emit Harvest(msg.sender, currentPerformanceFee);
            }
        }
    }

    function currentHarvestAmount(address _rewardToken)
        public
        view
        returns (uint256, uint256)
    {
        uint256 until = block.timestamp;
        if (until > end) {
            until = end;
        }
        uint256 diff = until.sub(lastHarvestedTime);

        uint256 index = 0;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (address(rewardTokens[i]) == _rewardToken) {
                index = i;
                break;
            }
        }

        uint256 harvestAmount = 0;
        if (fixedAPYPool) {
            // for fixed pools the stakingAPYs variable
            // contains a percentage value
            // to ensure a fixed amount of rewards
            harvestAmount = balanceOf()
                .mul(stakingAPYs[index])
                .mul(diff)
                .div(BP_DECIMALS)
                .div(YEAR_IN_SECONDS);
        } else {
            // for dynamic pools, the stakingAPYs variable
            // contains the token amount rewarded to the
            // pool for each second
            // so it is high for low participation
            // and low for high participation
            harvestAmount = stakingAPYs[index].mul(diff);
        }
        return (harvestAmount, until);
    }

    // function getCurrentUserBalance(address _user)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     (uint256 harvestAfterFees, ) = currentHarvestAmount()
    //         .mul(BP_DECIMALS.sub(performanceFee))
    //         .div(BP_DECIMALS);
    //     uint256 balanceAfterHarvest = balanceOf().add(harvestAfterFees);
    //     if (totalStaked == 0) {
    //         return 0;
    //     }
    //     return balanceAfterHarvest.mul(userInfo[_user].stake).div(totalStaked);
    // }

    // function getCurrentUserInfo(address _user)
    //     external
    //     view
    //     returns (
    //         uint256,
    //         uint256,
    //         uint256
    //     )
    // {
    //     return (
    //         getCurrentUserBalance(_user),
    //         userInfo[_user].deposits,
    //         userInfo[_user].shares
    //     );
    // }

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
