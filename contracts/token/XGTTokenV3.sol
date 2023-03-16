// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./BlacklistableUpgradeable.sol";

// Notes from Baal
// - Blacklisting currently set to block to/from, making any blacklisted address completely radioactive.
//   - Changing blacklisting to only from prevents blacklisted from spending, but does not block reception.
//   - The policy for this should be defined prior to deploying in prod.
// - A limit of 20% is placed on all taxes (prevents governance from setting 100% and stealing all funds).
// - Original token minted directly to the different addresses. The current token mints to the deployer.
// - As always, testing, testing, testing!

contract XionGlobalToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20SnapshotUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, UUPSUpgradeable, BlacklistableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");
    bytes32 public constant TAX_ROLE = keccak256("TAX_ROLE");

    address public taxReceiver;
    uint16 public buyTaxBps;
    uint16 public sellTaxBps;
    uint16 public transferTaxBps;
    mapping(address => bool) excludedFromTax;

    EnumerableSet.AddressSet private swapV2Pairs;

    event TaxReceiverSet(address indexed receiver);
    event TaxesSet(uint16 buyTaxBps, uint16 sellTaxBps, uint16 transferTaxBps);
    event ExcludedFromTax(address indexed target);
    event IncludedInTax(address indexed target);
    event NewTaxableSwapPair(address indexed pair);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __ERC20_init("Xion Global Token", "XGTv3");
        __ERC20Burnable_init();
        __ERC20Snapshot_init();
        __AccessControl_init();
        __Pausable_init();
        __ERC20Permit_init("Xion Global Token");
        __ERC20Votes_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(BLACKLISTER_ROLE, msg.sender);
        _grantRole(TAX_ROLE, msg.sender);

        _mint(msg.sender, 1000000000 * 10 ** decimals());

        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function snapshot() public onlyRole(SNAPSHOT_ROLE) {
        _snapshot();
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function blacklist(address account) public onlyRole(BLACKLISTER_ROLE) {
        _blacklist(account);
    }

    function unblacklist(address account) public onlyRole(BLACKLISTER_ROLE) {
        _unblacklist(account);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (excludedFromTax[to]) {
            _transfer(msg.sender, to, amount);
        } else {
            if (sellTaxBps > 0 && swapV2Pairs.contains(to)) {
                _transferTaxed(to, amount, sellTaxBps);
            } else if (buyTaxBps > 0 && swapV2Pairs.contains(msg.sender)) {
                _transferTaxed(to, amount, buyTaxBps);
            } else if (transferTaxBps > 0){
                _transferTaxed(to, amount, transferTaxBps);
            } else {
                _transfer(msg.sender, to, amount);
            }
        }
        return true;
    }

    function _transferTaxed(address to, uint256 amount, uint16 taxBps) private {
        uint256 taxAmount = amount * taxBps / 10000;
        uint256 leftAmount = amount - taxAmount;
        _transfer(msg.sender, taxReceiver, taxAmount);
        _transfer(msg.sender, to, leftAmount);
    }

    function setTaxReceiver(address receiver) external onlyRole(TAX_ROLE) {
        require(receiver != address(0), "XGTv3: Cannot set tax receiver to the zero address!");
        taxReceiver = receiver;
        emit TaxReceiverSet(receiver);
    }

    function setTaxes(uint16 buyTax, uint16 sellTax, uint16 transferTax) external onlyRole(TAX_ROLE) {
        require(buyTaxBps <= 2000, "XGTv3: buy tax is too high!");
        require(sellTaxBps <= 2000, "XGTv3: sell tax is too high!");
        require(transferTaxBps <= 2000, "XGTv3: transfer tax is too high!");
        buyTaxBps = buyTax;
        sellTaxBps = sellTax;
        transferTaxBps = transferTax;
        emit TaxesSet(buyTax, sellTax, transferTax);
    }

    function excludeFromTax(address target) external onlyRole(TAX_ROLE) {
        excludedFromTax[target] = true;
        emit ExcludedFromTax(target);
    }

    function includeInTax(address target) external onlyRole(TAX_ROLE) {
        excludedFromTax[target] = false;
        emit IncludedInTax(target);
    }

    function addTaxableSwapPair(address pairAddress) external onlyRole(TAX_ROLE) {
        require(!swapV2Pairs.contains(pairAddress), "XGTv3: SwapV2Pair already added");
        swapV2Pairs.add(pairAddress);
        emit NewTaxableSwapPair(pairAddress);
    }

    function isTaxablePair(address pair) public view returns (bool) {
        return EnumerableSet.contains(swapV2Pairs, pair);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        notBlacklisted(from)
        notBlacklisted(to)
        override(ERC20Upgradeable, ERC20SnapshotUpgradeable)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._burn(account, amount);
    }
}
