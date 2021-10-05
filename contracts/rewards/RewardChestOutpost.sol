// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../metatx/EIP712MetaTransaction.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRewardModule.sol";
import "../interfaces/IXGTTokenHomeBridge.sol";

contract RewardChestOutpost is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712MetaTransaction
{
    using SafeMathUpgradeable for uint256;

    IERC20 public xgt;

    address[] public modules;
    mapping(address => bool) public isActiveModule;

    mapping(address => uint256) public userBalance;

    bool public paused;

    mapping(address => bool) public authorizedAddress;

    event PauseStateChanged(address performer, bool paused);

    function initialize(address _multiSig, address _xgt) public initializer {
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_multiSig);
        xgt = IERC20(_xgt);
    }

    function toggleModule(address _module, bool _active) external onlyOwner {
        isActiveModule[_module] = _active;
        if (_active) {
            modules.push(_module);
        } else {
            for (uint256 i = 0; i < modules.length; i++) {
                if (modules[i] == _module) {
                    if (i != modules.length - 1) {
                        modules[i] = modules[modules.length - 1];
                    }
                    modules.pop();
                    break;
                }
            }
        }
    }

    function pauseContract(bool _pause) external onlyOwner {
        paused = _pause;
        emit PauseStateChanged(msgSender(), _pause);
    }

    function toggleAuthorizedAddress(address _address, bool _authorized)
        external
        onlyOwner
    {
        authorizedAddress[_address] = _authorized;
    }

    function addToBalance(address _user, uint256 _amount)
        external
        onlyModule
        returns (bool)
    {
        userBalance[_user] = userBalance[_user].add(_amount);
        return true;
    }

    function claim() external nonReentrant returns (uint256 withdrawAmount) {
        if (paused) {
            return 0;
        }

        for (uint256 i = 0; i < modules.length; i++) {
            IRewardModule(modules[i]).claimModule(msgSender());
        }

        withdrawAmount = userBalance[msgSender()];
        userBalance[msgSender()] = 0;

        require(
            xgt.transfer(msgSender(), withdrawAmount),
            "XGT-REWARD-CHEST-WITHDRAW-TRANSFER-FAILED"
        );

        return withdrawAmount;
    }

    function sendInstantClaim(address _user, uint256 _amount)
        external
        nonReentrant
        onlyModule
        returns (bool)
    {
        require(
            xgt.transfer(_user, _amount),
            "XGT-REWARD-CHEST-INSTANT-CLAIM-TRANSFER-FAILED"
        );
        return true;
    }

    function getClaimableBalance(address _user)
        external
        view
        returns (uint256)
    {
        // withdrawable balance
        uint256 total = userBalance[_user];

        for (uint256 i = 0; i < modules.length; i++) {
            total = total.add(IRewardModule(modules[i]).getClaimable(_user));
        }

        return total;
    }

    modifier onlyModule() {
        require(
            isActiveModule[msgSender()],
            "XGT-REWARD-CHEST-NOT-AUTHORIZED-MODULE"
        );
        _;
    }
}
