// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRewardChest.sol";
import "../interfaces/IPoolModule.sol";

contract CashbackModule is Initializable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    IERC20 public xgt;
    IRewardChest public rewardChest;
    IPoolModule public poolModule;

    address public subscriptionContract;
    uint256 public lockupTime;

    struct Cashback {
        uint256 amount;
        uint256 claimedAmount;
        uint256 vestingStart;
        uint256 vestingEnd;
    }

    mapping(address => Cashback[]) public cashbacks;

    struct CashbackLevel {
        uint256 tvlRequired;
        uint256 totalAmount;
        uint256 usedAmount;
    }

    mapping(uint256 => CashbackLevel) public cashbackLevels;
    uint256 highestCashbackLevel;

    mapping(address => Cashback[]) public monthlyCashbacks;

    event CashbackAdded(
        address indexed recipient,
        uint256 amountInUSD,
        uint256 amountInXGT,
        uint256 vestingEnd
    );
    event CashbackClaimed(address indexed recipient, uint256 amount);

    function initialize(
        address _xgt,
        address _rewardChest,
        address _poolModule,
        address _subscriptionContract,
        uint256 _lockupTime
    ) public initializer {
        xgt = IERC20(_xgt);
        rewardChest = IRewardChest(_rewardChest);
        poolModule = IPoolModule(_poolModule);
        subscriptionContract = _subscriptionContract;
        lockupTime = _lockupTime;
        highestCashbackLevel = 0;

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(rewardChest.owner());
    }

    function changeSubscriptionContract(address _newSubscriptionContract)
        external
        onlyOwner
    {
        subscriptionContract = _newSubscriptionContract;
    }

    function updateCashbackLevel(
        uint256 _level,
        uint256 _tvlRequired,
        uint256 _totalAmount
    ) external onlyOwner {
        cashbackLevels[_level].tvlRequired = _tvlRequired;
        cashbackLevels[_level].totalAmount = _totalAmount;
        if (cashbackLevels[_level].usedAmount > _totalAmount) {
            cashbackLevels[_level].usedAmount = _totalAmount;
        }
        if (_level > highestCashbackLevel) {
            highestCashbackLevel = _level;
        }
    }

    function addCashback(address _recipient, uint256 _amount)
        external
        onlySubscriptionContract
    {
        if (_amount > 0) {
            uint256 cashbackAmount = _processCashback(_amount);
            if (cashbackAmount > 0) {
                uint256 amountInXGT = cashbackAmount.mul(10**18).div(
                    poolModule.getCurrentAverageXGTPrice()
                );
                uint256 startTime = _getStartTime(block.timestamp);
                uint256 endTime = startTime.add(lockupTime);
                if (lockupTime > 0) {
                    bool found = false;
                    uint256 emptyIndex = 2**256 - 1;
                    for (
                        uint256 i = 0;
                        i < monthlyCashbacks[_recipient].length;
                        i++
                    ) {
                        if (
                            monthlyCashbacks[_recipient][i].vestingStart ==
                            startTime
                        ) {
                            monthlyCashbacks[_recipient][i]
                                .amount = monthlyCashbacks[_recipient][i]
                                .amount
                                .add(amountInXGT);
                            found = true;
                            break;
                        }
                        // if there is an empty entry and it's the first we find, store it
                        if (
                            monthlyCashbacks[_recipient][i].amount == 0 &&
                            emptyIndex == 2**256 - 1
                        ) {
                            emptyIndex = i;
                        }
                    }
                    if (!found) {
                        // if we havent found the right entry
                        // but found an empty one, lets now use this one
                        if (emptyIndex < 2**256 - 1) {
                            monthlyCashbacks[_recipient][emptyIndex]
                                .amount = amountInXGT;
                            monthlyCashbacks[_recipient][emptyIndex]
                                .claimedAmount = 0;
                            monthlyCashbacks[_recipient][emptyIndex]
                                .vestingStart = startTime;
                            monthlyCashbacks[_recipient][emptyIndex]
                                .vestingEnd = endTime;
                        } else {
                            // otherwise lets create a new one
                            monthlyCashbacks[_recipient].push(
                                Cashback(amountInXGT, 0, startTime, endTime)
                            );
                        }
                    }
                } else {
                    require(
                        rewardChest.sendInstantClaim(_recipient, amountInXGT),
                        "CASHBACK-MODULE-INSTANT-CLAIM-FAILED"
                    );
                }

                emit CashbackAdded(
                    _recipient,
                    cashbackAmount,
                    amountInXGT,
                    endTime
                );
            }
        }
    }

    function manualOverrideCashback(address _user, uint256 _amount)
        external
        onlyOwner
    {
        uint256 startTime = _getStartTime(block.timestamp);
        uint256 endTime = startTime.add(lockupTime);
        if (monthlyCashbacks[_user].length == 0) {
            monthlyCashbacks[_user].push(
                Cashback(_amount, 0, startTime, endTime)
            );
        } else {
            for (uint256 i = 0; i < monthlyCashbacks[_user].length; i++) {
                if (monthlyCashbacks[_user][i].vestingStart == startTime) {
                    monthlyCashbacks[_user][i].amount = monthlyCashbacks[_user][
                        i
                    ].amount.add(_amount);
                }
            }
        }
    }

    function manualResetOfOldStructure(
        address _user,
        uint256 _from,
        uint256 _to
    ) external onlyOwner {
        if (cashbacks[_user].length - 1 < _to) {
            _to = cashbacks[_user].length - 1;
        }
        for (uint256 i = _from; i <= _to; i++) {
            delete cashbacks[_user][i];
        }
    }

    function manualUpdateFromOldCashbackStructure(
        address _user,
        uint256 _from,
        uint256 _to
    ) external {
        if (cashbacks[_user].length - 1 < _to) {
            _to = cashbacks[_user].length - 1;
        }
        for (uint256 i = _from; i <= _to; i++) {
            if (
                cashbacks[_user][i].amount > 0 &&
                cashbacks[_user][i].claimedAmount < cashbacks[_user][i].amount
            ) {
                uint256 newTime = _getStartTime(
                    cashbacks[_user][i].vestingStart
                );
                if (monthlyCashbacks[_user].length == 0) {
                    monthlyCashbacks[_user].push(
                        Cashback(0, 0, newTime, newTime.add(lockupTime))
                    );
                }

                monthlyCashbacks[_user][0].amount = monthlyCashbacks[_user][0]
                    .amount
                    .add(cashbacks[_user][i].amount);
                monthlyCashbacks[_user][0].claimedAmount = monthlyCashbacks[
                    _user
                ][0].claimedAmount.add(cashbacks[_user][i].claimedAmount);
            }
            delete cashbacks[_user][i];
        }
    }

    function _processCashback(uint256 _amount) internal returns (uint256) {
        uint256 currentTVL = poolModule.getTotalValue();
        uint256 cashbackLeftToProcess = _amount;
        for (uint256 i = 1; i <= highestCashbackLevel; i++) {
            if (
                cashbackLevels[i].tvlRequired > 0 &&
                cashbackLevels[i].tvlRequired <= currentTVL &&
                cashbackLevels[i].totalAmount > cashbackLevels[i].usedAmount
            ) {
                uint256 leftOnThisLevel = cashbackLevels[i].totalAmount.sub(
                    cashbackLevels[i].usedAmount
                );
                if (leftOnThisLevel >= cashbackLeftToProcess) {
                    cashbackLevels[i].usedAmount = cashbackLevels[i]
                        .usedAmount
                        .add(cashbackLeftToProcess);
                    cashbackLeftToProcess = 0;
                    break;
                } else {
                    cashbackLeftToProcess = cashbackLeftToProcess.sub(
                        leftOnThisLevel
                    );
                    cashbackLevels[i].usedAmount = cashbackLevels[i]
                        .totalAmount;
                }
            }
        }
        return _amount.sub(cashbackLeftToProcess);
    }

    // We group airdrops by months, so we calculate the timestamp of the beginning
    // of the current month. Technically we are using 1/12th of the seconds
    // in a year, which still divides the year into 12 parts.
    function _getStartTime(uint256 _now) internal pure returns (uint256) {
        uint256 systemStart = 1635724800; // November 1st, 2021 Midnight UTC
        uint256 month = 2628000; // one month
        uint256 numMonths = (_now.sub(systemStart)).div(month); // how many months since start
        return systemStart.add((month.mul(numMonths)));
    }

    function getClaimable(address _recipient) external view returns (uint256) {
        uint256 total = 0;
        if (monthlyCashbacks[_recipient].length > 0) {
            for (uint256 i = 0; i < monthlyCashbacks[_recipient].length; i++) {
                if (
                    monthlyCashbacks[_recipient][i].amount > 0 &&
                    monthlyCashbacks[_recipient][i].amount >
                    monthlyCashbacks[_recipient][i].claimedAmount
                ) {
                    uint256 fullAmount = monthlyCashbacks[_recipient][i].amount;
                    uint256 paid = monthlyCashbacks[_recipient][i]
                        .claimedAmount;
                    uint256 totalDuration = monthlyCashbacks[_recipient][i]
                        .vestingEnd
                        .sub(monthlyCashbacks[_recipient][i].vestingStart);
                    uint256 passedDuration = block.timestamp.sub(
                        monthlyCashbacks[_recipient][i].vestingStart
                    );
                    uint256 partInBP = passedDuration.mul(10000).div(
                        totalDuration
                    );
                    uint256 dueNow = monthlyCashbacks[_recipient][i]
                        .amount
                        .mul(partInBP)
                        .div(10000);
                    if (paid.add(dueNow) > fullAmount) {
                        dueNow = fullAmount.sub(paid);
                    }
                    total = total.add(dueNow);
                }
            }
        }
        return total;
    }

    function claimModule(address _recipient) external {
        if (monthlyCashbacks[_recipient].length > 0) {
            uint256 totalDue = 0;
            for (uint256 i = 0; i < monthlyCashbacks[_recipient].length; i++) {
                if (
                    monthlyCashbacks[_recipient][i].amount > 0 &&
                    monthlyCashbacks[_recipient][i].amount >
                    monthlyCashbacks[_recipient][i].claimedAmount
                ) {
                    uint256 fullAmount = monthlyCashbacks[_recipient][i].amount;
                    uint256 paid = monthlyCashbacks[_recipient][i]
                        .claimedAmount;
                    uint256 totalDuration = monthlyCashbacks[_recipient][i]
                        .vestingEnd
                        .sub(monthlyCashbacks[_recipient][i].vestingStart);
                    uint256 passedDuration = block.timestamp.sub(
                        monthlyCashbacks[_recipient][i].vestingStart
                    );
                    uint256 partInBP = passedDuration.mul(10000).div(
                        totalDuration
                    );
                    uint256 dueNow = monthlyCashbacks[_recipient][i]
                        .amount
                        .mul(partInBP)
                        .div(10000);
                    if (paid.add(dueNow) > fullAmount) {
                        dueNow = fullAmount.sub(paid);
                        monthlyCashbacks[_recipient][i]
                            .claimedAmount = fullAmount;
                    } else {
                        monthlyCashbacks[_recipient][i].claimedAmount = paid
                            .add(dueNow);
                    }
                    totalDue = totalDue.add(dueNow);
                    emit CashbackClaimed(
                        _recipient,
                        monthlyCashbacks[_recipient][i].amount
                    );
                    if (
                        fullAmount ==
                        monthlyCashbacks[_recipient][i].claimedAmount
                    ) {
                        delete monthlyCashbacks[_recipient][i];
                    }
                }
            }
            if (totalDue > 0) {
                require(
                    rewardChest.addToBalance(_recipient, totalDue),
                    "XGT-REWARD-MODULE-FAILED-TO-ADD-TO-BALANCE"
                );
            }
        }
    }

    function getCashbackLevelDetails(uint256 _level)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            cashbackLevels[_level].tvlRequired,
            cashbackLevels[_level].totalAmount,
            cashbackLevels[_level].usedAmount
        );
    }

    function currentCashbackLeft() public view returns (uint256, uint256) {
        uint256 currentTVL = poolModule.getTotalValue();
        uint256 cashbackLeft = 0;
        uint256 currentLevel = 0;
        for (uint256 i = 1; i <= highestCashbackLevel; i++) {
            if (
                cashbackLevels[i].tvlRequired > 0 &&
                cashbackLevels[i].tvlRequired <= currentTVL
            ) {
                cashbackLeft = cashbackLeft
                    .add(cashbackLevels[i].totalAmount)
                    .sub(cashbackLevels[i].usedAmount);
                currentLevel = i;
            }
        }
        return (currentLevel, cashbackLeft);
    }

    function checkPurchaseForCashback(uint256 _amount)
        public
        view
        returns (uint256, uint256)
    {
        (, uint256 cashbackLeft) = currentCashbackLeft();
        uint256 cashbackAmount = _amount;
        if (_amount > cashbackLeft) {
            cashbackAmount = cashbackLeft;
        }
        return (
            cashbackAmount,
            cashbackAmount.mul(10**18).div(
                poolModule.getCurrentAverageXGTPrice()
            )
        );
    }

    modifier onlyRewardChest() {
        require(
            msg.sender == address(rewardChest),
            "XGT-REWARD-CHEST-NOT-AUTHORIZED"
        );
        _;
    }

    modifier onlySubscriptionContract() {
        require(
            msg.sender == address(subscriptionContract),
            "XGT-REWARD-CHEST-NOT-AUTHORIZED"
        );
        _;
    }
}
