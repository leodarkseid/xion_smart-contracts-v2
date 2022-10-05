// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.7.6;

// Baal: check version of openzeppelin
import "@openzeppelin/contracts-upgradeable@3.4.0/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@3.4.0/utils/PausableUpgradeable.sol";
import "../interfaces/IXGHub.sol";

contract XGFeatureRegistry is OwnableUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    IXGHub public hub;

    mapping(address => mapping(bytes32 => bool)) public unlockedFeatures;
    mapping(address => bytes32[]) public unlockedFeaturesOfUser;

    function initialize(address _hub) external initializer {
        hub = IXGHub(_hub);

        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        transferOwnership(OwnableUpgradeable(address(hub)).owner());
    }

    function updateXGHub(address _hub) external onlyOwner {
        hub = IXGHub(_hub);
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
            hub.getAuthorizationStatus(msg.sender) || msg.sender == owner(),
            "Not authorized"
        );
        _;
    }

    modifier onlyHub() {
        require(msg.sender == address(hub), "Not authorized");
        _;
    }
}
