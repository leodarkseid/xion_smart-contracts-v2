// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract XGFeatureRegistry is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    address public hub;

    mapping(address => bool) public authorized;
    mapping(address => mapping(bytes32 => bool)) public unlockedFeatures;
    mapping(address => bytes32[]) public unlockedFeaturesOfUser;

    function initialize(address _hub, address _owner) external initializer {
        hub = _hub;

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(_owner);
    }

    function updateXGHub(address _hub) external onlyOwner {
        hub = _hub;
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

    function toggleFeatureUnlock(
        address _user,
        string calldata _featureDescriptor,
        bool _active
    ) external onlyAuthorized whenNotPaused {
        bytes32 descriptor = keccak256(abi.encode(_featureDescriptor));
        if (_active && !unlockedFeatures[_user][descriptor]) {
            unlockedFeaturesOfUser[_user].push(descriptor);
        }
        if (!_active && unlockedFeatures[_user][descriptor]) {
            if (unlockedFeaturesOfUser[_user].length > 1) {
                for (
                    uint256 i = 0;
                    i < unlockedFeaturesOfUser[_user].length;
                    i++
                ) {
                    // if found
                    if (unlockedFeaturesOfUser[_user][i] == descriptor) {
                        // if it's not the last element, replace with last element
                        if (i != unlockedFeaturesOfUser[_user].length - 1) {
                            unlockedFeaturesOfUser[_user][
                                i
                            ] = unlockedFeaturesOfUser[_user][
                                unlockedFeaturesOfUser[_user].length - 1
                            ];
                        }
                        break;
                    }
                }
            }
            unlockedFeaturesOfUser[_user].pop();
        }
        unlockedFeatures[_user][descriptor] = _active;
    }

    function getFeatureUnlockStatus(
        address _user,
        string calldata _featureDescriptor
    ) external view returns (bool) {
        return
            unlockedFeatures[_user][keccak256(abi.encode(_featureDescriptor))];
    }

    function getUnlockedFeaturesOfUser(address _user)
        external
        view
        returns (bytes32[] memory)
    {
        return unlockedFeaturesOfUser[_user];
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
}
