// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IDRALib} from "./IDRALib.sol";

contract IDRA is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ============ ROLE DEFINITIONS ============

    /// @dev Role for minting new tokens (assigned to backend service wallet)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @dev Role for burning tokens from any address (for admin burns)
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @dev Role for pausing/unpausing all token transfers
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Role for adding/removing addresses from blacklist
    bytes32 public constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");

    /// @dev Role for upgrading contract implementation
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev Role for initiating and completing bridge requests (burning on source chain, minting on destination chain)
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    // ============ STORAGE VARIABLES ============

    /// @dev Mapping to track blacklisted addresses
    mapping(address => bool) private _blacklisted;

    /// @dev Chain ID where this contract is deployed
    uint256 public chainId;

    /// @dev Single bridge fee amount applied to all destination chains
    uint256 public bridgeFee;

    /// @dev Address that collects bridge fees
    address public feeCollector;

    /// @dev Mapping to track completed bridge requests (bridgeId => completed)
    mapping(bytes32 => bool) private _completedBridges;

    /// @dev Counter for bridge nonces on source chain (prevents replay attacks)
    mapping(address => uint256) private _bridgeNonces;

    /// @dev Track used nonces on destination chain to prevent nonce replay
    mapping(bytes32 => bool) private _usedNonces;

    /// @dev Storage gap for future upgrades (preserves storage layout)
    uint256[50] private _gap;

    // ============ CUSTOM ERRORS ============

    error NotMinter();
    error NotBurner();
    error NotPauser();
    error NotBlacklister();
    error NotUpgrader();
    error BlacklistedAddress(address account);
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 available, uint256 required);
    error ContractPaused();
    error NotBridgeRole();
    error InvalidChainId();
    error InvalidBridgeRequest();
    error BridgeAlreadyCompleted(bytes32 bridgeId);
    error InsufficientFee(uint256 required, uint256 provided);

    // ============ EVENTS ============

    /// @dev Emitted when tokens are minted
    event Minted(address indexed to, uint256 amount, address indexed minter);

    /// @dev Emitted when tokens are burned
    event Burned(address indexed from, uint256 amount, address indexed burner);

    /// @dev Emitted when an address is blacklisted
    event Blacklisted(address indexed account, address indexed by);

    /// @dev Emitted when an address is unblacklisted
    event Unblacklisted(address indexed account, address indexed by);

    /// @dev Emitted when a bridge request is created (tokens burned on source chain)
    event BridgeRequest(
        bytes32 indexed bridgeId,
        address indexed from,
        uint256 indexed destinationChainId,
        address to,
        uint256 amount,
        uint256 fee,
        uint256 nonce
    );

    /// @dev Emitted when a bridge is completed (tokens minted on destination chain)
    event BridgeCompleted(
        bytes32 indexed bridgeId,
        address indexed to,
        uint256 amount,
        address indexed bridgeRelayer
    );

    /// @dev Emitted when global bridge fee is updated
    event BridgeFeeUpdated(uint256 oldFee, uint256 newFee);

    /// @dev Emitted when fee collector address is updated
    event FeeCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );

    // ============ INITIALIZATION ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract with required parameters
     * @param name Token name (e.g., "MyStableCoin")
     * @param symbol Token symbol (e.g., "MSC")
     * @param defaultAdmin Address receiving DEFAULT_ADMIN_ROLE
     * @param minter Address receiving MINTER_ROLE (backend service)
     * @param pauser Address receiving PAUSER_ROLE
     * @param blacklister Address receiving BLACKLISTER_ROLE
     */
    function initialize(
        string memory name,
        string memory symbol,
        address defaultAdmin,
        address minter,
        address burner,
        address pauser,
        address blacklister
    ) public initializer {
        // Initialize parent contracts
        __ERC20_init(name, symbol);
        __ERC20Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // Validate addresses
        if (defaultAdmin == address(0)) revert ZeroAddress();
        if (minter == address(0)) revert ZeroAddress();
        if (pauser == address(0)) revert ZeroAddress();
        if (blacklister == address(0)) revert ZeroAddress();

        // Set up role
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(BURNER_ROLE, burner);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(BLACKLISTER_ROLE, blacklister);

        // Grant UPGRADER_ROLE to defaultAdmin for upgrade capability
        _grantRole(UPGRADER_ROLE, defaultAdmin);
        _grantRole(BRIDGE_ROLE, defaultAdmin);

        // Initialize chain ID (using block.chainid for current chain)
        chainId = block.chainid;
    }

    // ============ MINTING FUNCTIONALITY ============

    /**
     * @dev Mint new tokens to specified address
     * @param to Recipient address
     * @param amount Amount to mint (in smallest unit, e.g., wei equivalent)
     * @return true on success
     */
    function mint(
        address to,
        uint256 amount
    )
        external
        virtual
        onlyRole(MINTER_ROLE)
        whenNotPaused
        notBlacklisted(to)
        returns (bool)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _mint(to, amount);
        emit Minted(to, amount, msg.sender);
        return true;
    }

    // ============ BURNING FUNCTIONALITY ============

    /**
     * @dev Admin burn: burn tokens from any address (no allowance required)
     * Note: This function intentionally does NOT check blacklist status to allow
     * emergency recovery of tokens from compromised/blacklisted addresses
     * @param from Address to burn tokens from
     * @param amount Amount to burn
     * @return true on success
     */
    function burnFrom(
        address from,
        uint256 amount
    )
        external
        virtual
        onlyRole(BURNER_ROLE)
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(from) < amount) {
            revert InsufficientBalance(balanceOf(from), amount);
        }

        // Note: Blacklist check intentionally omitted to allow emergency recovery
        // Admin burns should work even on blacklisted addresses for security purposes
        _burn(from, amount);
        emit Burned(from, amount, msg.sender);
        return true;
    }

    // ============ PAUSE/UNPAUSE FUNCTIONALITY ============

    /**
     * @dev Pause all token transfers, minting, and burning
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause all token transfers, minting, and burning
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ BLACKLIST FUNCTIONALITY ============

    /**
     * @dev Modifier to check if address is not blacklisted
     * @param account Address to check
     */
    modifier notBlacklisted(address account) {
        if (_blacklisted[account]) revert BlacklistedAddress(account);
        _;
    }

    /**
     * @dev Add address to blacklist
     * @param account Address to blacklist
     */
    function blacklist(address account) external onlyRole(BLACKLISTER_ROLE) {
        if (account == address(0)) revert ZeroAddress();
        _blacklisted[account] = true;
        emit Blacklisted(account, msg.sender);
    }

    /**
     * @dev Remove address from blacklist
     * @param account Address to unblacklist
     */
    function unblacklist(address account) external onlyRole(BLACKLISTER_ROLE) {
        _blacklisted[account] = false;
        emit Unblacklisted(account, msg.sender);
    }

    /**
     * @dev Check if address is blacklisted
     * @param account Address to check
     * @return true if blacklisted, false otherwise
     */
    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    // ============ TRANSFER OVERRIDE ============

    /**
     * @dev Override ERC20 transfer mechanism
     * Required override for multiple inheritance from ERC20Upgradeable and ERC20PausableUpgradeable
     * Blacklist checks are handled in transfer() and transferFrom() functions via modifier
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     */
    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
        whenNotPaused
    {
        super._update(from, to, amount);
    }

    /**
     * @dev Override transfer to add blacklist checks
     * @param to Recipient address
     * @param amount Transfer amount
     * @return true on success
     */
    function transfer(
        address to,
        uint256 amount
    )
        public
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        return super.transfer(to, amount);
    }

    /**
     * @dev Override transferFrom to add blacklist checks
     * @param from Sender address
     * @param to Recipient address
     * @param amount Transfer amount
     * @return true on success
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        override
        whenNotPaused
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    // ============ UPGRADE FUNCTIONALITY ============

    /**
     * @dev Authorize upgrade (only UPGRADER_ROLE can upgrade)
     * @param newImplementation Address of new implementation contract
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {
        // Additional validation can be added here if needed
    }

    // ============ BRIDGE FUNCTIONALITY ============

    /**
     * @dev Request to bridge tokens to another chain
     * burns tokens from user's address on source chain and emits event for bridge completion
     * @param destinationChainId Chain ID of destination chain
     * @param from Address to burn tokens from (user's address)
     * @param amount Amount of tokens to bridge (will be burned from user)
     * @param to Recipient address on destination chain
     * @return bridgeId Unique identifier for this bridge request
     */
    function bridgeRequest(
        uint256 destinationChainId,
        address from,
        uint256 amount,
        address to
    )
        external
        onlyRole(BRIDGE_ROLE)
        whenNotPaused
        nonReentrant
        returns (bytes32 bridgeId)
    {
        if (destinationChainId == 0) revert InvalidChainId();
        if (destinationChainId == chainId) revert InvalidChainId();
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_blacklisted[from]) revert BlacklistedAddress(from);
        if (_blacklisted[to]) revert BlacklistedAddress(to);
        if (balanceOf(from) < amount) {
            revert InsufficientBalance(balanceOf(from), amount);
        }

        uint256 fee = bridgeFee;

        // Calculate total amount needed (amount + fee)
        uint256 totalNeeded = amount + fee;
        if (balanceOf(from) < totalNeeded) {
            revert InsufficientBalance(balanceOf(from), totalNeeded);
        }

        // Increment nonce for this user address (prevents replay attacks)
        uint256 nonce = _bridgeNonces[from]++;

        // Generate unique bridge ID using shared library
        bridgeId = IDRALib.computeBridgeId(
            from,
            destinationChainId,
            to,
            amount,
            nonce,
            chainId
        );

        // Check if this bridge ID was already used (unlikely but check for safety)
        if (_completedBridges[bridgeId]) {
            revert BridgeAlreadyCompleted(bridgeId);
        }

        // Burn the tokens from user's address (amount + fee)
        _burn(from, totalNeeded);

        // Transfer fee to fee collector if set
        if (fee > 0 && feeCollector != address(0)) {
            _mint(feeCollector, fee);
        }

        emit BridgeRequest(
            bridgeId,
            from,
            destinationChainId,
            to,
            amount,
            fee,
            nonce
        );
        emit Burned(from, totalNeeded, msg.sender);

        return bridgeId;
    }

    /**
     * @dev Complete bridge request by minting tokens on destination chain (admin-only)
     * Only callable by accounts with BRIDGE_ROLE
     * Validates bridge request by recomputing bridgeId from source parameters
     * @param from Source address that had tokens burned on source chain
     * @param sourceChainId Chain ID where bridge request was created
     * @param to Recipient address on destination chain
     * @param amount Amount of tokens to mint
     * @param nonce Nonce used in the bridge request on source chain
     * @return true on success
     */
    function completeBridge(
        address from,
        uint256 sourceChainId,
        address to,
        uint256 amount,
        uint256 nonce
    )
        external
        onlyRole(BRIDGE_ROLE)
        whenNotPaused
        nonReentrant
        notBlacklisted(to)
        returns (bool)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (from == address(0)) revert ZeroAddress();
        if (sourceChainId == 0) revert InvalidChainId();
        if (sourceChainId == chainId) revert InvalidChainId();

        // Recompute bridgeId from source parameters using shared library
        bytes32 bridgeId = IDRALib.computeBridgeId(
            from,
            chainId, // destinationChainId (this chain)
            to,
            amount,
            nonce,
            sourceChainId
        );

        // Validate bridge request hasn't been completed (prevents replay)
        if (_completedBridges[bridgeId]) {
            revert BridgeAlreadyCompleted(bridgeId);
        }

        // Track used nonces per address+sourceChain to prevent nonce replay attacks
        // A nonce can only be used once per (address, sourceChain) combination
        bytes32 nonceKey = keccak256(
            abi.encodePacked(from, nonce, sourceChainId)
        );
        if (_usedNonces[nonceKey]) {
            revert InvalidBridgeRequest();
        }

        // Mark this nonce as used
        _usedNonces[nonceKey] = true;

        // Mark bridge as completed (prevents double completion)
        _completedBridges[bridgeId] = true;

        // Mint tokens to recipient
        _mint(to, amount);

        emit BridgeCompleted(bridgeId, to, amount, msg.sender);
        emit Minted(to, amount, msg.sender);

        return true;
    }

    /**
     * @dev Check if a bridge request has been completed
     * @param bridgeId Bridge request ID to check
     * @return true if bridge is completed, false otherwise
     */
    function isBridgeCompleted(bytes32 bridgeId) external view returns (bool) {
        return _completedBridges[bridgeId];
    }

    /**
     * @dev Get the next bridge nonce for an address
     * @param account Address to get nonce for
     * @return Next nonce that will be used for bridge request
     */
    function getBridgeNonce(address account) external view returns (uint256) {
        return _bridgeNonces[account];
    }

    // ============ BRIDGE FEE MANAGEMENT ============

    /**
     * @dev Set global bridge fee (applies to all chains)
     * Only callable by DEFAULT_ADMIN_ROLE
     * @param fee Fee amount in token units
     */
    function setBridgeFee(uint256 fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldFee = bridgeFee;
        bridgeFee = fee;

        emit BridgeFeeUpdated(oldFee, fee);
    }

    /**
     * @dev Get the global bridge fee
     * @return Fee amount in token units
     */
    function getBridgeFee() external view returns (uint256) {
        return bridgeFee;
    }

    /**
     * @dev Set the address that collects bridge fees
     * Only callable by DEFAULT_ADMIN_ROLE
     * @param collector Address to receive bridge fees
     */
    function setFeeCollector(
        address collector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (collector == address(0)) revert ZeroAddress();

        address oldCollector = feeCollector;
        feeCollector = collector;

        emit FeeCollectorUpdated(oldCollector, collector);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * Override to return 2 decimals instead of default 18.
     * For example, a balance of 505 tokens should be displayed as 5.05 (505 / 10 ** 2).
     * @return Number of decimals (2)
     */
    function decimals() public pure override returns (uint8) {
        return 2;
    }

    /**
     * @dev Get the current implementation version
     * @return version string
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    /**
     * @dev Check if contract supports interface
     * @param interfaceId Interface ID to check
     * @return true if supported
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlEnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
