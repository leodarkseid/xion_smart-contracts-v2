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
        uint256 cashbackAmount = _processCashback(_amount);
        if (cashbackAmount > 0) {
            uint256 amountInXGT = cashbackAmount.mul(10**18).div(
                poolModule.getCurrentAverageXGTPrice()
            );
            uint256 vestingEnd = block.timestamp.add(lockupTime);
            if (lockupTime > 0) {
                cashbacks[_recipient].push(
                    Cashback(amountInXGT, 0, block.timestamp, vestingEnd)
                );
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
                vestingEnd
            );
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

    function getClaimable(address _recipient) external view returns (uint256) {
        uint256 total = 0;
        if (cashbacks[_recipient].length > 0) {
            for (uint256 i = 0; i < cashbacks[_recipient].length; i++) {
                uint256 fullAmount = cashbacks[_recipient][i].amount;
                uint256 paid = cashbacks[_recipient][i].claimedAmount;
                uint256 totalDuration = cashbacks[_recipient][i].vestingEnd.sub(
                    cashbacks[_recipient][i].vestingStart
                );
                uint256 passedDuration = block.timestamp.sub(
                    cashbacks[_recipient][i].vestingStart
                );
                uint256 partInBP = passedDuration.mul(10000).div(totalDuration);
                uint256 dueNow = cashbacks[_recipient][i]
                    .amount
                    .mul(partInBP)
                    .div(10000);
                if (paid.add(dueNow) > fullAmount) {
                    dueNow = fullAmount.sub(paid);
                }
                total = total.add(dueNow);
            }
        }
        return total;
    }

    function claimModule(address _recipient) external {
        if (cashbacks[_recipient].length > 0) {
            Cashback[] storage newCashbackArray;
            for (uint256 i = 0; i < cashbacks[_recipient].length; i++) {
                uint256 fullAmount = cashbacks[_recipient][i].amount;
                uint256 paid = cashbacks[_recipient][i].claimedAmount;
                uint256 totalDuration = cashbacks[_recipient][i].vestingEnd.sub(
                    cashbacks[_recipient][i].vestingStart
                );
                uint256 passedDuration = block.timestamp.sub(
                    cashbacks[_recipient][i].vestingStart
                );
                uint256 partInBP = passedDuration.mul(10000).div(totalDuration);
                uint256 dueNow = cashbacks[_recipient][i]
                    .amount
                    .mul(partInBP)
                    .div(10000);
                if (paid.add(dueNow) > fullAmount) {
                    dueNow = fullAmount.sub(paid);
                    cashbacks[_recipient][i].claimedAmount = fullAmount;
                } else {
                    cashbacks[_recipient][i].claimedAmount = paid.add(dueNow);
                }

                require(
                    rewardChest.addToBalance(_recipient, dueNow),
                    "XGT-REWARD-MODULE-FAILED-TO-ADD-TO-BALANCE"
                );
                emit CashbackClaimed(
                    _recipient,
                    cashbacks[_recipient][i].amount
                );
                if (fullAmount > cashbacks[_recipient][i].claimedAmount) {
                    newCashbackArray.push(cashbacks[_recipient][i]);
                }
            }
            cashbacks[_recipient] = newCashbackArray;
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
