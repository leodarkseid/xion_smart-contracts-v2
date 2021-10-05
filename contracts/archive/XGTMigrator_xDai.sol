// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "../interfaces/IRewardChest.sol";

contract XGTMigratorXDai {
    using SafeMath for uint256;

    mapping(address => bool) public controllers;

    ERC20Burnable public oldToken;
    IERC20 public newToken;
    IRewardChest public rewardChest;

    uint256 public exchangeRate = 650;
    uint256 public lastPriceV1 = 130000000000000000;
    uint256 public startTime = 1625673600;
    uint256 public endTime = 1627488000;

    constructor(
        address _oldToken,
        address _newToken,
        address _rewardChest,
        address _controller
    ) {
        oldToken = ERC20Burnable(_oldToken);
        newToken = IERC20(_newToken);
        rewardChest = IRewardChest(_rewardChest);
        controllers[_controller] = true;
    }

    function toggleControllers(address _controller, bool _state)
        external
        onlyController
    {
        controllers[_controller] = _state;
    }

    // if any base currency gets stuck we can free it
    function sweepBase(uint256 _amount) external onlyController {
        msg.sender.transfer(_amount);
    }

    fallback() external payable {}

    receive() external payable {}

    function migrate() external {
        _migrate(msg.sender, msg.sender);
    }

    function migrateTo(address _receiver) external {
        _migrate(msg.sender, _receiver);
    }

    function migrateFor(address _from) external onlyController {
        _migrate(_from, _from);
    }

    function _migrate(address _from, address _to) internal {
        require(
            block.timestamp >= startTime && block.timestamp <= endTime,
            "MIGRATOR-NOT-OPENED-YET"
        );
        uint256 finalReturnXGT = 0;

        // XGT TOKEN
        // Check whether user has XGT v1
        uint256 migrationAmountXGT = oldToken.balanceOf(_from);

        // If user has v1, transfer them here
        if (migrationAmountXGT > 0) {
            require(
                oldToken.transferFrom(_from, address(this), migrationAmountXGT),
                "MIGRATOR-TRANSFER-OLD-TOKEN-FAILED"
            );
        } else {
            return;
        }

        oldToken.burn(migrationAmountXGT);
        finalReturnXGT = (migrationAmountXGT.mul(exchangeRate)).div(1000);

        rewardChest.sendInstantClaim(_to, finalReturnXGT);
    }

    function setLastPriceV1(uint256 _lastPriceV1) external onlyController {
        // for the input
        // e.g. $0.13 per XGT would be 130000000000000000 (0.13 * 10^18)
        lastPriceV1 = _lastPriceV1;
    }

    function updateExchangeRate(uint256 _currentPriceV2)
        external
        onlyController
    {
        // for the input
        // e.g. $0.20 per XGT would be 200000000000000000 (0.2 * 10^18)
        exchangeRate = (lastPriceV1.mul(1000)).div(_currentPriceV2);
    }

    modifier onlyController() {
        require(controllers[msg.sender], "not controller");
        _;
    }
}
