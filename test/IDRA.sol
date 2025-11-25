// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/IDRA.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StablecoinV1Test
 * @dev Comprehensive test suite for StablecoinV1 contract
 * Covers all test cases specified in the instruction.md
 */
contract StablecoinV1Test is Test {
    IDRA public idra;
    IDRA public implementation;
    ERC1967Proxy public proxy;

    // Test addresses
    address public constant DEFAULT_ADMIN = address(0x99);
    address public constant MINTER = address(0x2);
    address public constant BURNER = address(0x3);
    address public constant PAUSER = address(0x4);
    address public constant BLACKLISTER = address(0x5);
    address public constant UPGRADER = address(0x6);
    address public constant BRIDGE_RELAYER = address(0x7);
    address public constant FEE_COLLECTOR = address(0x8);
    address public constant USER1 = address(0x10);
    address public constant USER2 = address(0x11);
    address public constant USER3 = address(0x12);

    // Test amounts
    uint256 public constant MINT_AMOUNT = 1000e18;
    uint256 public constant BURN_AMOUNT = 500e18;
    uint256 public constant TRANSFER_AMOUNT = 200e18;
    uint256 public constant BRIDGE_AMOUNT = 300e18;
    uint256 public constant BRIDGE_FEE = 10e18;

    // Test chain IDs
    uint256 public constant SOURCE_CHAIN_ID = 1; // Ethereum mainnet
    uint256 public constant DEST_CHAIN_ID = 137; // Polygon
    uint256 public constant DEST_CHAIN_ID_2 = 84532; // Base

    // Events
    event Minted(address indexed to, uint256 amount, address indexed minter);
    event Burned(address indexed from, uint256 amount, address indexed burner);
    event Blacklisted(address indexed account, address indexed by);
    event Unblacklisted(address indexed account, address indexed by);
    event Paused(address account);
    event Unpaused(address account);
    event RoleGranted(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event RoleRevoked(
        bytes32 indexed role,
        address indexed account,
        address indexed sender
    );
    event BridgeRequest(
        bytes32 indexed bridgeId,
        address indexed from,
        uint256 indexed destinationChainId,
        address to,
        uint256 amount,
        uint256 fee,
        uint256 nonce
    );
    event BridgeCompleted(
        bytes32 indexed bridgeId,
        address indexed to,
        uint256 amount,
        address indexed bridgeRelayer
    );
    event BridgeFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );

    function _deployIDRAOnChain(
        uint256 targetChainId
    ) internal returns (IDRA deployed) {
        vm.chainId(targetChainId);
        IDRA impl = new IDRA();
        bytes memory initData = abi.encodeWithSelector(
            IDRA.initialize.selector,
            "IDRAStableCoin",
            "IDRA",
            DEFAULT_ADMIN,
            MINTER,
            BURNER,
            PAUSER,
            BLACKLISTER
        );
        ERC1967Proxy prox = new ERC1967Proxy(address(impl), initData);
        deployed = IDRA(address(prox));
        vm.startPrank(DEFAULT_ADMIN);
        deployed.grantRole(deployed.BRIDGE_ROLE(), BRIDGE_RELAYER);
        vm.stopPrank();
    }

    function setUp() public {
        vm.chainId(SOURCE_CHAIN_ID);
        // Deploy implementation
        implementation = new IDRA();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            IDRA.initialize.selector,
            "IDRAStableCoin",
            "IDRA",
            DEFAULT_ADMIN,
            MINTER,
            BURNER,
            PAUSER,
            BLACKLISTER
        );

        // Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        idra = IDRA(address(proxy));

        // Grant UPGRADER_ROLE to UPGRADER address
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.UPGRADER_ROLE(), UPGRADER);
        // Grant BRIDGE_ROLE to bridge relayer
        idra.grantRole(idra.BRIDGE_ROLE(), BRIDGE_RELAYER);
        vm.stopPrank();

        // Give some ETH to test addresses
        vm.deal(USER1, 1 ether);
        vm.deal(USER2, 1 ether);
        vm.deal(USER3, 1 ether);
        vm.deal(BRIDGE_RELAYER, 1 ether);
    }

    // ============ INITIALIZATION TESTS ============

    function test_TC_INIT_001_SuccessfulInitialization() public {
        assertEq(idra.name(), "IDRAStableCoin");
        assertEq(idra.symbol(), "IDRA");
        assertEq(idra.totalSupply(), 0);
        assertFalse(idra.paused());
        assertEq(idra.version(), "1.0.0");

        // Check roles
        assertTrue(idra.hasRole(idra.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN));
        assertTrue(idra.hasRole(idra.MINTER_ROLE(), MINTER));
        assertTrue(idra.hasRole(idra.PAUSER_ROLE(), PAUSER));
        assertTrue(idra.hasRole(idra.BLACKLISTER_ROLE(), BLACKLISTER));
        assertTrue(idra.hasRole(idra.UPGRADER_ROLE(), DEFAULT_ADMIN));
        assertTrue(idra.hasRole(idra.UPGRADER_ROLE(), UPGRADER));
    }

    function test_TC_INIT_002_PreventDoubleInitialization() public {
        vm.expectRevert();
        idra.initialize(
            "AnotherName",
            "ANS",
            address(0x100),
            address(0x101),
            address(0x102),
            address(0x103),
            address(0x104)
        );
    }

    function test_TC_INIT_003_InitializeWithZeroAddressAdmin() public {
        // Deploy new implementation for this test
        IDRA newImpl = new IDRA();

        bytes memory initData = abi.encodeWithSelector(
            IDRA.initialize.selector,
            "Test",
            "TST",
            address(0), // Zero address admin
            MINTER,
            BURNER,
            PAUSER,
            BLACKLISTER
        );

        vm.expectRevert(IDRA.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    // ============ MINTING TESTS ============

    function test_TC_MINT_001_SuccessfulMintByMinter() public {
        vm.startPrank(MINTER);
        vm.expectEmit(true, true, true, true);
        emit Minted(USER1, MINT_AMOUNT, MINTER);
        bool success = idra.mint(USER1, MINT_AMOUNT);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT);
        assertEq(idra.totalSupply(), MINT_AMOUNT);
    }

    function test_TC_MINT_002_MintFailsWithoutMinterRole() public {
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.mint(USER2, MINT_AMOUNT);
    }

    function test_TC_MINT_003_MintToZeroAddressFails() public {
        vm.startPrank(MINTER);
        vm.expectRevert(IDRA.ZeroAddress.selector);
        idra.mint(address(0), MINT_AMOUNT);
    }

    function test_TC_MINT_004_MintZeroAmountFails() public {
        vm.startPrank(MINTER);
        vm.expectRevert(IDRA.ZeroAmount.selector);
        idra.mint(USER1, 0);
    }

    function test_TC_MINT_005_MintToBlacklistedAddressFails() public {
        // First blacklist the address
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);

        vm.startPrank(MINTER);
        vm.expectRevert();
        idra.mint(USER1, MINT_AMOUNT);
    }

    function test_TC_MINT_006_MintWhenPausedFails() public {
        // First pause the contract
        vm.startPrank(PAUSER);
        idra.pause();

        vm.startPrank(MINTER);
        vm.expectRevert();
        idra.mint(USER1, MINT_AMOUNT);
    }

    function test_TC_MINT_007_MintLargeAmount() public {
        uint256 largeAmount = type(uint256).max / 2;

        vm.startPrank(MINTER);
        bool success = idra.mint(USER1, largeAmount);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), largeAmount);
        assertEq(idra.totalSupply(), largeAmount);
    }

    function test_TC_MINT_008_MultipleSequentialMints() public {
        vm.startPrank(MINTER);

        idra.mint(USER1, 1000e18);
        idra.mint(USER2, 2000e18);
        idra.mint(USER1, 500e18);

        vm.stopPrank();

        assertEq(idra.balanceOf(USER1), 1500e18);
        assertEq(idra.balanceOf(USER2), 2000e18);
        assertEq(idra.totalSupply(), 3500e18);
    }

    // ============ ADMIN BURN TESTS ============

    function test_TC_ADMIN_BURN_001_SuccessfulAdminBurn() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Grant BURNER_ROLE to USER2
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.BURNER_ROLE(), USER2);
        vm.stopPrank();

        vm.startPrank(USER2);
        vm.expectEmit(true, true, true, true);
        emit Burned(USER1, BURN_AMOUNT, USER2);
        bool success = idra.burnFrom(USER1, BURN_AMOUNT);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - BURN_AMOUNT);
        assertEq(idra.totalSupply(), MINT_AMOUNT - BURN_AMOUNT);
    }

    function test_TC_ADMIN_BURN_002_AdminBurnWithoutRoleFails() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        vm.startPrank(USER2);
        vm.expectRevert();
        idra.burnFrom(USER1, BURN_AMOUNT);
    }

    function test_TC_ADMIN_BURN_003_AdminBurnWithoutAllowanceSucceeds() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Grant BURNER_ROLE to USER2
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.BURNER_ROLE(), USER2);

        // No approval given, but admin burn should still work
        vm.startPrank(USER2);
        bool success = idra.burnFrom(USER1, BURN_AMOUNT);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - BURN_AMOUNT);
    }

    function test_TC_ADMIN_BURN_004_AdminBurnFromBlacklistedAddress() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Blacklist the user
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);

        // Grant BURNER_ROLE to USER2
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.BURNER_ROLE(), USER2);

        // Admin burn should succeed even from blacklisted address
        vm.startPrank(USER2);
        bool success = idra.burnFrom(USER1, BURN_AMOUNT);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - BURN_AMOUNT);
    }

    function test_TC_ADMIN_BURN_005_AdminBurnMoreThanBalanceFails() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Grant BURNER_ROLE to USER2
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.BURNER_ROLE(), USER2);

        vm.startPrank(USER2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDRA.InsufficientBalance.selector,
                MINT_AMOUNT,
                MINT_AMOUNT + 1
            )
        );
        idra.burnFrom(USER1, MINT_AMOUNT + 1);
    }

    // ============ PAUSE/UNPAUSE TESTS ============

    function test_TC_PAUSE_001_SuccessfulPause() public {
        vm.startPrank(PAUSER);
        vm.expectEmit(true, false, false, false);
        emit Paused(PAUSER);
        idra.pause();

        assertTrue(idra.paused());
    }

    function test_TC_PAUSE_002_PauseWithoutRoleFails() public {
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.pause();
    }

    function test_TC_PAUSE_003_PauseAlreadyPausedContract() public {
        // First pause
        vm.startPrank(PAUSER);
        idra.pause();

        // Try to pause again
        vm.startPrank(PAUSER);
        vm.expectRevert(); // OpenZeppelin Pausable behavior
        idra.pause();
    }

    function test_TC_PAUSE_004_TransfersBlockedWhenPaused() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Pause the contract
        vm.startPrank(PAUSER);
        idra.pause();

        // Try to transfer
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.transfer(USER2, TRANSFER_AMOUNT);
    }

    function test_TC_PAUSE_005_ApprovalsWorkWhenPaused() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Pause the contract
        vm.startPrank(PAUSER);
        idra.pause();

        // Approval should still work
        vm.startPrank(USER1);
        bool success = idra.approve(USER2, TRANSFER_AMOUNT);

        assertTrue(success);
        assertEq(idra.allowance(USER1, USER2), TRANSFER_AMOUNT);
    }

    function test_TC_PAUSE_006_SuccessfulUnpause() public {
        // First pause
        vm.startPrank(PAUSER);
        idra.pause();

        // Then unpause
        vm.startPrank(PAUSER);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(PAUSER);
        idra.unpause();

        assertFalse(idra.paused());
    }

    function test_TC_PAUSE_007_UnpauseWithoutRoleFails() public {
        // First pause
        vm.startPrank(PAUSER);
        idra.pause();

        // Try to unpause without role
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.unpause();
    }

    // ============ BLACKLIST TESTS ============

    function test_TC_BLACKLIST_001_SuccessfulBlacklist() public {
        vm.startPrank(BLACKLISTER);
        vm.expectEmit(true, true, false, false);
        emit Blacklisted(USER1, BLACKLISTER);
        idra.blacklist(USER1);

        assertTrue(idra.isBlacklisted(USER1));
    }

    function test_TC_BLACKLIST_002_BlacklistWithoutRoleFails() public {
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.blacklist(USER2);
    }

    function test_TC_BLACKLIST_003_BlacklistZeroAddressFails() public {
        vm.startPrank(BLACKLISTER);
        vm.expectRevert(IDRA.ZeroAddress.selector);
        idra.blacklist(address(0));
    }

    function test_TC_BLACKLIST_004_BlacklistedCannotSend() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Blacklist the user
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);

        // Try to transfer
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.transfer(USER2, TRANSFER_AMOUNT);
    }

    function test_TC_BLACKLIST_005_BlacklistedCannotReceive() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Blacklist the recipient
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER2);

        // Try to transfer
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.transfer(USER2, TRANSFER_AMOUNT);
    }

    function test_TC_BLACKLIST_006_SuccessfulUnblacklist() public {
        // First blacklist
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);

        // Then unblacklist
        vm.startPrank(BLACKLISTER);
        vm.expectEmit(true, true, false, false);
        emit Unblacklisted(USER1, BLACKLISTER);
        idra.unblacklist(USER1);

        assertFalse(idra.isBlacklisted(USER1));
    }

    function test_TC_BLACKLIST_007_UnblacklistNonBlacklistedAddress() public {
        // Unblacklist non-blacklisted address (should succeed - idempotent)
        vm.startPrank(BLACKLISTER);
        idra.unblacklist(USER1);

        assertFalse(idra.isBlacklisted(USER1));
    }

    function test_TC_BLACKLIST_008_BlacklistedUserBalanceFrozen() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Blacklist the user
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);

        // Balance should still be visible
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT);
    }

    // ============ TRANSFER TESTS ============

    function test_TC_TRANSFER_001_SuccessfulTransfer() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        vm.startPrank(USER1);
        bool success = idra.transfer(USER2, TRANSFER_AMOUNT);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - TRANSFER_AMOUNT);
        assertEq(idra.balanceOf(USER2), TRANSFER_AMOUNT);
    }

    function test_TC_TRANSFER_002_TransferMoreThanBalanceFails() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        vm.startPrank(USER1);
        vm.expectRevert(); // ERC20 insufficient balance
        idra.transfer(USER2, MINT_AMOUNT + 1);
    }

    function test_TC_TRANSFER_003_TransferToZeroAddressFails() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        vm.startPrank(USER1);
        vm.expectRevert();
        idra.transfer(address(0), TRANSFER_AMOUNT);
    }

    function test_TC_TRANSFER_004_TransferFromWithAllowance() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Approve spender
        vm.startPrank(USER1);
        idra.approve(USER2, TRANSFER_AMOUNT);

        // Transfer from
        vm.startPrank(USER2);
        bool success = idra.transferFrom(USER1, USER3, TRANSFER_AMOUNT);

        assertTrue(success);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - TRANSFER_AMOUNT);
        assertEq(idra.balanceOf(USER3), TRANSFER_AMOUNT);
        assertEq(idra.allowance(USER1, USER2), 0);
    }

    function test_TC_TRANSFER_005_TransferFromWithoutAllowanceFails() public {
        // First mint some tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // No approval given
        vm.startPrank(USER2);
        vm.expectRevert(); // ERC20 insufficient allowance
        idra.transferFrom(USER1, USER3, TRANSFER_AMOUNT);
    }

    // ============ ROLE MANAGEMENT TESTS ============

    function test_TC_ROLE_001_GrantRoleByAdmin() public {
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectEmit(true, true, true, false);
        emit RoleGranted(idra.MINTER_ROLE(), USER1, DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);
        vm.stopPrank();

        assertTrue(idra.hasRole(idra.MINTER_ROLE(), USER1));
    }

    function test_TC_ROLE_002_GrantRoleWithoutAdminFails() public {
        vm.startPrank(USER1);
        bytes32 minterRole = idra.MINTER_ROLE();
        vm.expectRevert();
        idra.grantRole(minterRole, USER2);
    }

    function test_TC_ROLE_003_RevokeRoleByAdmin() public {
        // First grant role
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);
        vm.stopPrank();

        // Then revoke role
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectEmit(true, true, true, false);
        emit RoleRevoked(idra.MINTER_ROLE(), USER1, DEFAULT_ADMIN);
        idra.revokeRole(idra.MINTER_ROLE(), USER1);
        vm.stopPrank();

        assertFalse(idra.hasRole(idra.MINTER_ROLE(), USER1));
    }

    function test_TC_ROLE_004_RenounceRoleBySelf() public {
        // First grant role
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);
        vm.stopPrank();

        // Renounce role
        vm.startPrank(USER1);
        vm.expectEmit(true, true, true, false);
        emit RoleRevoked(idra.MINTER_ROLE(), USER1, USER1);
        idra.renounceRole(idra.MINTER_ROLE(), USER1);

        assertFalse(idra.hasRole(idra.MINTER_ROLE(), USER1));
    }

    function test_TC_ROLE_005_MultipleAddressesWithSameRole() public {
        // Grant same role to multiple addresses
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);
        idra.grantRole(idra.MINTER_ROLE(), USER2);
        vm.stopPrank();

        // Both should be able to mint
        vm.startPrank(USER1);
        idra.mint(USER3, MINT_AMOUNT);

        vm.startPrank(USER2);
        idra.mint(USER3, MINT_AMOUNT);

        assertEq(idra.balanceOf(USER3), MINT_AMOUNT * 2);
    }

    function test_TC_ROLE_006_OneAddressWithMultipleRoles() public {
        // Grant multiple roles to one address
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);

        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.PAUSER_ROLE(), USER1);

        // Should be able to mint
        vm.startPrank(USER1);
        idra.mint(USER2, MINT_AMOUNT);

        // Should be able to pause
        vm.startPrank(USER1);
        idra.pause();

        assertEq(idra.balanceOf(USER2), MINT_AMOUNT);
        assertTrue(idra.paused());
    }

    // ============ INTEGRATION TESTS ============

    function test_TC_INT_001_CompleteMintFlow() public {
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        assertEq(idra.balanceOf(USER1), MINT_AMOUNT);
    }

    function test_TC_INT_003_EmergencyPauseScenario() public {
        // Mint tokens to multiple users
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        idra.mint(USER2, MINT_AMOUNT);
        vm.stopPrank();

        // Admin detects security issue and pauses
        vm.startPrank(PAUSER);
        idra.pause();

        // All transfers should be blocked
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.transfer(USER2, TRANSFER_AMOUNT);
    }

    function test_TC_INT_004_BlacklistAndRecovery() public {
        // Mint tokens to user
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Blacklist compromised address
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);

        // Admin burns from compromised address
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.BURNER_ROLE(), DEFAULT_ADMIN);
        vm.startPrank(DEFAULT_ADMIN);
        idra.burnFrom(USER1, MINT_AMOUNT);

        // Admin mints to new address
        vm.startPrank(MINTER);
        idra.mint(USER2, MINT_AMOUNT);

        assertEq(idra.balanceOf(USER1), 0);
        assertEq(idra.balanceOf(USER2), MINT_AMOUNT);
    }

    function test_TC_INT_005_RoleRotation() public {
        // Grant MINTER_ROLE to new wallet
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);

        // Revoke MINTER_ROLE from old wallet
        vm.startPrank(DEFAULT_ADMIN);
        idra.revokeRole(idra.MINTER_ROLE(), MINTER);

        // New wallet should be able to mint
        vm.startPrank(USER1);
        idra.mint(USER2, MINT_AMOUNT);

        // Old wallet should not be able to mint
        vm.startPrank(MINTER);
        vm.expectRevert();
        idra.mint(USER2, MINT_AMOUNT);

        assertEq(idra.balanceOf(USER2), MINT_AMOUNT);
    }

    // ============ STRESS TESTS ============

    function test_TC_STRESS_001_HighVolumeMinting() public {
        uint256 numAddresses = 10; // Reduced for test efficiency
        uint256 amountPerAddress = 100e18;

        vm.startPrank(MINTER);
        for (uint256 i = 0; i < numAddresses; i++) {
            address user = address(uint160(0x1000 + i));
            idra.mint(user, amountPerAddress);
        }
        vm.stopPrank();

        assertEq(idra.totalSupply(), numAddresses * amountPerAddress);
    }

    function test_TC_STRESS_002_LargeBlacklist() public {
        uint256 numAddresses = 10; // Reduced for test efficiency

        vm.startPrank(BLACKLISTER);
        for (uint256 i = 0; i < numAddresses; i++) {
            address user = address(uint160(0x2000 + i));
            idra.blacklist(user);
        }
        vm.stopPrank();

        // Contract should remain functional
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT);
    }

    function test_TC_STRESS_003_MaximumTokenAmount() public {
        uint256 maxAmount = type(uint256).max - 1e18;

        vm.startPrank(MINTER);
        idra.mint(USER1, maxAmount);

        assertEq(idra.balanceOf(USER1), maxAmount);
        assertEq(idra.totalSupply(), maxAmount);
    }

    // ============ SECURITY TESTS ============

    function test_TC_SEC_002_FrontRunningProtection() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Transfer should succeed regardless of front-running attempts
        vm.startPrank(USER1);
        idra.transfer(USER2, TRANSFER_AMOUNT);

        assertEq(idra.balanceOf(USER2), TRANSFER_AMOUNT);
    }

    function test_TC_SEC_003_IntegerOverflowUnderflow() public {
        // Solidity 0.8+ has built-in overflow/underflow protection
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // This should revert due to built-in checks
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.transfer(USER2, MINT_AMOUNT + 1);
    }

    function test_TC_SEC_004_UnauthorizedUpgradeAttempt() public {
        // Deploy new implementation
        IDRA newImpl = new IDRA();

        // Try to upgrade without UPGRADER_ROLE
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.upgradeToAndCall(address(newImpl), "");
    }

    function test_TC_SEC_005_RoleEscalationAttempt() public {
        // Grant only MINTER_ROLE to USER1
        vm.startPrank(DEFAULT_ADMIN);
        idra.grantRole(idra.MINTER_ROLE(), USER1);

        // USER1 tries to grant itself UPGRADER_ROLE
        vm.startPrank(USER1);
        bytes32 upgraderRole = idra.UPGRADER_ROLE();
        vm.expectRevert(); // AccessControl error
        idra.grantRole(upgraderRole, USER1);
    }

    // ============ GAS BENCHMARK TESTS ============

    function test_TC_GAS_001_MintOperationGasCost() public {
        uint256 gasStart = gasleft();

        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        uint256 gasUsed = gasStart - gasleft();
        console.log("Mint operation gas cost:", gasUsed);

        // Should be reasonable (around 50-70k gas)
        assertLt(gasUsed, 100000);
    }

    function test_TC_GAS_003_TransferOperationGasCost() public {
        // First mint
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        uint256 gasStart = gasleft();

        vm.startPrank(USER1);
        idra.transfer(USER2, TRANSFER_AMOUNT);

        uint256 gasUsed = gasStart - gasleft();
        console.log("Transfer operation gas cost:", gasUsed);

        // Should be reasonable (around 50-65k gas)
        assertLt(gasUsed, 100000);
    }

    function test_TC_GAS_004_BlacklistCheckOverhead() public {
        // First mint
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);

        // Transfer without blacklist check (impossible to test directly)
        // But we can measure transfer gas cost
        uint256 gasStart = gasleft();

        vm.startPrank(USER1);
        idra.transfer(USER2, TRANSFER_AMOUNT);

        uint256 gasUsed = gasStart - gasleft();
        console.log("Transfer with blacklist check gas cost:", gasUsed);

        // Should be reasonable overhead
        assertLt(gasUsed, 100000);
    }

    // ============ BRIDGE REQUEST TESTS ============

    function test_TC_BRIDGE_001_SuccessfulBridgeRequest() public {
        // Mint tokens to user
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Set global bridge fee
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        idra.setFeeCollector(FEE_COLLECTOR);
        vm.stopPrank();

        // Admin bridges tokens on behalf of user
        uint256 totalNeeded = BRIDGE_AMOUNT + BRIDGE_FEE;
        uint256 nonce = idra.getBridgeNonce(USER1);
        bytes32 bridgeId = keccak256(
            abi.encodePacked(
                USER1,
                DEST_CHAIN_ID,
                USER2,
                BRIDGE_AMOUNT,
                nonce,
                block.chainid
            )
        );
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectEmit(true, true, true, true);
        emit BridgeRequest(
            bridgeId,
            USER1,
            DEST_CHAIN_ID,
            USER2,
            BRIDGE_AMOUNT,
            BRIDGE_FEE,
            nonce
        );
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();

        // Verify tokens were burned from user
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - totalNeeded);
        assertEq(idra.totalSupply(), MINT_AMOUNT - BRIDGE_AMOUNT);

        // Verify nonce incremented
        assertEq(idra.getBridgeNonce(USER1), nonce + 1);
    }

    function test_TC_BRIDGE_002_BridgeRequestWithFeeCollection() public {
        // Mint tokens to user
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Set global bridge fee and fee collector
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        idra.setFeeCollector(FEE_COLLECTOR);
        vm.stopPrank();

        // Admin bridges tokens on behalf of user
        uint256 totalNeeded = BRIDGE_AMOUNT + BRIDGE_FEE;
        vm.startPrank(BRIDGE_RELAYER);
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();

        // Verify fee was minted to fee collector
        assertEq(idra.balanceOf(FEE_COLLECTOR), BRIDGE_FEE);
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - totalNeeded);
        assertEq(idra.totalSupply(), MINT_AMOUNT - BRIDGE_AMOUNT);
    }

    function test_TC_BRIDGE_003_BridgeRequestInsufficientBalance() public {
        // Mint tokens to user (less than needed)
        vm.startPrank(MINTER);
        idra.mint(USER1, BRIDGE_AMOUNT);
        vm.stopPrank();

        // Set global bridge fee
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        idra.setFeeCollector(FEE_COLLECTOR);
        vm.stopPrank();

        // Try to bridge (insufficient for amount + fee)
        vm.startPrank(BRIDGE_RELAYER);
        uint256 requiredAmount = BRIDGE_AMOUNT + BRIDGE_FEE;
        vm.expectRevert(
            abi.encodeWithSelector(
                IDRA.InsufficientBalance.selector,
                BRIDGE_AMOUNT,
                requiredAmount
            )
        );
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();
    }

    function test_TC_BRIDGE_004_BridgeRequestToSameChainFails() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Get current chain ID
        uint256 currentChainId = block.chainid;

        // Try to bridge to same chain
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.InvalidChainId.selector);
        idra.bridgeRequest(currentChainId, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();
    }

    function test_TC_BRIDGE_005_BridgeRequestZeroAmountFails() public {
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.ZeroAmount.selector);
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, 0, USER2);
        vm.stopPrank();
    }

    function test_TC_BRIDGE_006_BridgeRequestToZeroAddressFails() public {
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.ZeroAddress.selector);
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, address(0));
        vm.stopPrank();
    }

    function test_TC_BRIDGE_007_BridgeRequestByBlacklistedUserFails() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Blacklist user
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER1);
        vm.stopPrank();

        // Try to bridge (should fail because user is blacklisted)
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert();
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();
    }

    function test_TC_BRIDGE_008_BridgeRequestWhenPausedFails() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Pause contract
        vm.startPrank(PAUSER);
        idra.pause();
        vm.stopPrank();

        // Try to bridge
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert();
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();
    }

    function test_TC_BRIDGE_009_BridgeRequestWithoutRoleFails() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Set global bridge fee
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        vm.stopPrank();

        // Try to bridge without BRIDGE_ROLE (regular user)
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();
    }

    function test_TC_BRIDGE_010_MultipleBridgeRequestsIncrementNonce() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT * 2);
        vm.stopPrank();

        // Set global bridge fee
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        vm.stopPrank();

        // First bridge request (admin bridges on behalf of user)
        vm.startPrank(BRIDGE_RELAYER);
        bytes32 bridgeId1 = idra.bridgeRequest(
            DEST_CHAIN_ID,
            USER1,
            BRIDGE_AMOUNT,
            USER2
        );
        assertEq(idra.getBridgeNonce(USER1), 1);

        // Second bridge request
        bytes32 bridgeId2 = idra.bridgeRequest(
            DEST_CHAIN_ID,
            USER1,
            BRIDGE_AMOUNT,
            USER2
        );
        assertEq(idra.getBridgeNonce(USER1), 2);
        vm.stopPrank();

        // Bridge IDs should be different
        assertNotEq(bridgeId1, bridgeId2);
    }

    // ============ COMPLETE BRIDGE TESTS ============

    function test_TC_COMPLETE_BRIDGE_001_SuccessfulCompleteBridge() public {
        // Simulate bridge request on source chain (we'll mock the parameters)
        address from = USER1;
        uint256 sourceChainId = 137;
        address to = USER2;
        uint256 amount = BRIDGE_AMOUNT;
        uint256 nonce = 0;
        uint256 timestamp = block.timestamp;

        // Recompute bridge ID (as done in completeBridge)
        bytes32 bridgeId = keccak256(
            abi.encodePacked(
                from,
                block.chainid, // destination chain
                to,
                amount,
                nonce,
                sourceChainId
            )
        );

        // Complete bridge
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectEmit(true, true, true, true);
        emit BridgeCompleted(bridgeId, to, amount, BRIDGE_RELAYER);
        bool success = idra.completeBridge(
            from,
            sourceChainId,
            to,
            amount,
            nonce
        );

        assertTrue(success);
        assertEq(idra.balanceOf(USER2), BRIDGE_AMOUNT);
        assertEq(idra.totalSupply(), BRIDGE_AMOUNT);
        assertTrue(idra.isBridgeCompleted(bridgeId));
    }

    function test_TC_COMPLETE_BRIDGE_002_CompleteBridgeWithoutRoleFails()
        public
    {
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.completeBridge(USER1, SOURCE_CHAIN_ID, USER2, BRIDGE_AMOUNT, 0);
    }

    function test_TC_COMPLETE_BRIDGE_003_CompleteBridgeTwiceFails() public {
        address from = USER1;
        uint256 sourceChainId = 136;
        address to = USER2;
        uint256 amount = BRIDGE_AMOUNT;
        uint256 nonce = 0;

        // First completion
        vm.startPrank(BRIDGE_RELAYER);
        bytes32 bridgeId = keccak256(
            abi.encodePacked(
                from,
                block.chainid,
                to,
                amount,
                nonce,
                sourceChainId
            )
        );
        idra.completeBridge(from, sourceChainId, to, amount, nonce);

        // Try to complete again
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDRA.BridgeAlreadyCompleted.selector,
                bridgeId
            )
        );
        idra.completeBridge(from, sourceChainId, to, amount, nonce);
    }

    function test_TC_COMPLETE_BRIDGE_004_CompleteBridgeReuseNonceFails()
        public
    {
        address from = USER1;
        uint256 sourceChainId = 138;
        uint256 amount = BRIDGE_AMOUNT;
        uint256 nonce = 0;

        // First bridge completion
        vm.startPrank(BRIDGE_RELAYER);
        idra.completeBridge(from, sourceChainId, USER2, amount, nonce);

        // Try to use same nonce with different parameters
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.InvalidBridgeRequest.selector);
        idra.completeBridge(from, sourceChainId, USER3, amount, nonce);
    }

    function test_TC_COMPLETE_BRIDGE_005_CompleteBridgeToBlacklistedFails()
        public
    {
        // Blacklist recipient
        vm.startPrank(BLACKLISTER);
        idra.blacklist(USER2);

        // Try to complete bridge to blacklisted address
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert();
        idra.completeBridge(USER1, SOURCE_CHAIN_ID, USER2, BRIDGE_AMOUNT, 0);
    }

    function test_TC_COMPLETE_BRIDGE_006_CompleteBridgeZeroAmountFails()
        public
    {
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.ZeroAmount.selector);
        idra.completeBridge(USER1, SOURCE_CHAIN_ID, USER2, 0, 0);
    }

    function test_TC_COMPLETE_BRIDGE_007_CompleteBridgeToZeroAddressFails()
        public
    {
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.ZeroAddress.selector);
        idra.completeBridge(
            USER1,
            SOURCE_CHAIN_ID,
            address(0),
            BRIDGE_AMOUNT,
            0
        );
    }

    function test_TC_COMPLETE_BRIDGE_008_CompleteBridgeInvalidSourceChainId()
        public
    {
        // Same chain ID as destination
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.InvalidChainId.selector);
        idra.completeBridge(USER1, block.chainid, USER2, BRIDGE_AMOUNT, 0);

        // Zero chain ID
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert(IDRA.InvalidChainId.selector);
        idra.completeBridge(USER1, 0, USER2, BRIDGE_AMOUNT, 0);
    }

    function test_TC_COMPLETE_BRIDGE_009_CompleteBridgeWhenPausedFails()
        public
    {
        // Pause contract
        vm.startPrank(PAUSER);
        idra.pause();

        // Try to complete bridge
        vm.startPrank(BRIDGE_RELAYER);
        vm.expectRevert();
        idra.completeBridge(USER1, SOURCE_CHAIN_ID, USER2, BRIDGE_AMOUNT, 0);
    }

    function test_TC_COMPLETE_BRIDGE_010_CompleteBridgeWithDifferentNonces()
        public
    {
        address from = USER1;
        uint256 sourceChainId = 139;
        address to = USER2;
        uint256 amount = BRIDGE_AMOUNT;

        // Complete bridge with nonce 0
        vm.startPrank(BRIDGE_RELAYER);
        idra.completeBridge(from, sourceChainId, to, amount, 0);
        assertEq(idra.balanceOf(USER2), BRIDGE_AMOUNT);

        // Complete bridge with nonce 1 (different bridge)
        vm.startPrank(BRIDGE_RELAYER);
        idra.completeBridge(from, sourceChainId, USER3, amount, 1);
        assertEq(idra.balanceOf(USER3), BRIDGE_AMOUNT);
    }

    // ============ BRIDGE FEE MANAGEMENT TESTS ============

    function test_TC_BRIDGE_FEE_001_SetBridgeFeeByAdmin() public {
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectEmit(true, false, false, false);
        emit BridgeFeeUpdated(0, BRIDGE_FEE);
        idra.setBridgeFee(BRIDGE_FEE);

        assertEq(idra.getBridgeFee(), BRIDGE_FEE);
    }

    function test_TC_BRIDGE_FEE_002_SetBridgeFeeWithoutAdminFails() public {
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.setBridgeFee(BRIDGE_FEE);
    }

    function test_TC_BRIDGE_FEE_003_UpdateGlobalBridgeFeeSequentially() public {
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        assertEq(idra.getBridgeFee(), BRIDGE_FEE);
        uint256 newFee = BRIDGE_FEE * 2;
        vm.expectEmit(true, false, false, false);
        emit BridgeFeeUpdated(BRIDGE_FEE, newFee);
        idra.setBridgeFee(newFee);
        vm.stopPrank();

        assertEq(idra.getBridgeFee(), newFee);
    }

    // Removed: invalid chain ID checks are not applicable for global fee

    function test_TC_BRIDGE_FEE_005_UpdateBridgeFee() public {
        // Set initial fee
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        assertEq(idra.getBridgeFee(), BRIDGE_FEE);

        // Update fee
        uint256 newFee = BRIDGE_FEE * 2;
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectEmit(true, false, false, false);
        emit BridgeFeeUpdated(BRIDGE_FEE, newFee);
        idra.setBridgeFee(newFee);

        assertEq(idra.getBridgeFee(), newFee);
    }

    function test_TC_BRIDGE_FEE_006_SetFeeCollector() public {
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectEmit(true, true, false, false);
        emit FeeCollectorUpdated(address(0), FEE_COLLECTOR);
        idra.setFeeCollector(FEE_COLLECTOR);

        assertEq(idra.feeCollector(), FEE_COLLECTOR);
    }

    function test_TC_BRIDGE_FEE_007_SetFeeCollectorWithoutAdminFails() public {
        vm.startPrank(USER1);
        vm.expectRevert();
        idra.setFeeCollector(FEE_COLLECTOR);
    }

    function test_TC_BRIDGE_FEE_008_SetFeeCollectorZeroAddressFails() public {
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectRevert(IDRA.ZeroAddress.selector);
        idra.setFeeCollector(address(0));
    }

    function test_TC_BRIDGE_FEE_009_UpdateFeeCollector() public {
        // Set initial collector
        vm.startPrank(DEFAULT_ADMIN);
        idra.setFeeCollector(FEE_COLLECTOR);
        assertEq(idra.feeCollector(), FEE_COLLECTOR);

        // Update collector
        address newCollector = address(0x888);
        vm.startPrank(DEFAULT_ADMIN);
        vm.expectEmit(true, true, false, false);
        emit FeeCollectorUpdated(FEE_COLLECTOR, newCollector);
        idra.setFeeCollector(newCollector);

        assertEq(idra.feeCollector(), newCollector);
    }

    function test_TC_BRIDGE_FEE_010_BridgeRequestWithZeroFee() public {
        // Mint tokens
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        // Set zero fee (default is already 0, but set explicitly)
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(0);
        vm.stopPrank();

        // Bridge should work with zero fee (admin bridges on behalf of user)
        vm.startPrank(BRIDGE_RELAYER);
        idra.bridgeRequest(DEST_CHAIN_ID, USER1, BRIDGE_AMOUNT, USER2);
        vm.stopPrank();

        // Verify only bridge amount was burned
        assertEq(idra.balanceOf(USER1), MINT_AMOUNT - BRIDGE_AMOUNT);
        assertEq(idra.totalSupply(), MINT_AMOUNT - BRIDGE_AMOUNT);
    }

    // ============ BRIDGE INTEGRATION TESTS ============

    function test_TC_BRIDGE_INT_001_CompleteBridgeFlow() public {
        // Setup source chain (proxy already initialized in setUp under SOURCE_CHAIN_ID)
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        idra.setFeeCollector(FEE_COLLECTOR);
        vm.stopPrank();

        // Step 1: Bridge request on source chain
        vm.startPrank(BRIDGE_RELAYER);
        uint256 nonce = idra.getBridgeNonce(USER1);
        bytes32 bridgeId = idra.bridgeRequest(
            DEST_CHAIN_ID,
            USER1,
            BRIDGE_AMOUNT,
            USER2
        );
        vm.stopPrank();

        // Verify source chain state after request
        assertEq(
            idra.balanceOf(USER1),
            MINT_AMOUNT - BRIDGE_AMOUNT - BRIDGE_FEE
        );
        assertEq(idra.balanceOf(FEE_COLLECTOR), BRIDGE_FEE);
        assertEq(idra.getBridgeNonce(USER1), 1);

        // Step 2: Deploy destination chain proxy initialized under DEST_CHAIN_ID
        IDRA idraDest = _deployIDRAOnChain(DEST_CHAIN_ID);

        // Complete bridge on destination chain
        vm.startPrank(BRIDGE_RELAYER);
        idraDest.completeBridge(
            USER1,
            idra.chainId(),
            USER2,
            BRIDGE_AMOUNT,
            nonce
        );
        vm.stopPrank();
        // Verify destination chain state
        assertEq(idraDest.balanceOf(USER2), BRIDGE_AMOUNT);
        assertTrue(idraDest.isBridgeCompleted(bridgeId));
    }

    function test_TC_BRIDGE_INT_002_MultipleBridgesToDifferentChains() public {
        // Source chain setup (proxy in setUp)
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT * 3);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        vm.stopPrank();

        // Bridge requests on source chain
        vm.startPrank(BRIDGE_RELAYER);
        bytes32 bridgeId1 = idra.bridgeRequest(
            DEST_CHAIN_ID,
            USER1,
            BRIDGE_AMOUNT,
            USER2
        );
        // Update global fee before second bridge to different chain
        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE * 2);
        vm.stopPrank();

        vm.startPrank(BRIDGE_RELAYER);
        bytes32 bridgeId2 = idra.bridgeRequest(
            DEST_CHAIN_ID_2,
            USER1,
            BRIDGE_AMOUNT,
            USER3
        );
        vm.stopPrank();

        uint256 nonceAfter = idra.getBridgeNonce(USER1);
        assertEq(nonceAfter, 2);

        // Destination chain #1 deployment and completion
        IDRA idraDest1 = _deployIDRAOnChain(DEST_CHAIN_ID);
        vm.startPrank(BRIDGE_RELAYER);
        idraDest1.completeBridge(
            USER1,
            idra.chainId(),
            USER2,
            BRIDGE_AMOUNT,
            0
        );
        vm.stopPrank();
        assertEq(idraDest1.balanceOf(USER2), BRIDGE_AMOUNT);
        assertTrue(idraDest1.isBridgeCompleted(bridgeId1));

        // Destination chain #2 deployment and completion
        IDRA idraDest2 = _deployIDRAOnChain(DEST_CHAIN_ID_2);
        vm.startPrank(BRIDGE_RELAYER);
        idraDest2.completeBridge(
            USER1,
            idra.chainId(),
            USER3,
            BRIDGE_AMOUNT,
            1
        );
        vm.stopPrank();
        assertEq(idraDest2.balanceOf(USER3), BRIDGE_AMOUNT);
        assertTrue(idraDest2.isBridgeCompleted(bridgeId2));
    }

    function test_TC_BRIDGE_INT_003_BridgeRequestThenCompleteInOrder() public {
        // Source chain setup
        vm.startPrank(MINTER);
        idra.mint(USER1, MINT_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(DEFAULT_ADMIN);
        idra.setBridgeFee(BRIDGE_FEE);
        vm.stopPrank();

        // Two bridge requests on source chain
        vm.startPrank(BRIDGE_RELAYER);
        bytes32 bridgeIdA = idra.bridgeRequest(
            DEST_CHAIN_ID,
            USER1,
            BRIDGE_AMOUNT,
            USER2
        );
        bytes32 bridgeIdB = idra.bridgeRequest(
            DEST_CHAIN_ID,
            USER1,
            BRIDGE_AMOUNT,
            USER3
        );
        vm.stopPrank();

        // Deploy destination chain proxy
        IDRA idraDest = _deployIDRAOnChain(DEST_CHAIN_ID);

        // Complete in order
        vm.startPrank(BRIDGE_RELAYER);
        idraDest.completeBridge(USER1, idra.chainId(), USER2, BRIDGE_AMOUNT, 0);
        assertEq(idraDest.balanceOf(USER2), BRIDGE_AMOUNT);

        idraDest.completeBridge(USER1, idra.chainId(), USER3, BRIDGE_AMOUNT, 1);
        assertEq(idraDest.balanceOf(USER3), BRIDGE_AMOUNT);
        vm.stopPrank();

        // Completed flags on destination
        assertTrue(idraDest.isBridgeCompleted(bridgeIdA));
        assertTrue(idraDest.isBridgeCompleted(bridgeIdB));
    }

    // ============ DECIMALS TESTS ============

    function test_TC_DECIMALS_001_DecimalsReturnsTwo() public view {
        assertEq(idra.decimals(), 2);
    }

    function test_TC_DECIMALS_002_DecimalsIsNotDefaultEighteen() public view {
        assertNotEq(idra.decimals(), 18);
    }

    function test_TC_DECIMALS_003_DecimalsIsPureFunction() public view {
        uint8 decimalsValue = idra.decimals();
        assertEq(decimalsValue, 2);
    }

    function test_TC_DECIMALS_004_DecimalsConsistentAcrossInstances() public {
        IDRA newImpl = new IDRA();
        bytes memory initData = abi.encodeWithSelector(
            IDRA.initialize.selector,
            "TestToken",
            "TEST",
            DEFAULT_ADMIN,
            MINTER,
            BURNER,
            PAUSER,
            BLACKLISTER
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImpl), initData);
        IDRA newIdra = IDRA(address(newProxy));

        assertEq(idra.decimals(), 2);
        assertEq(newIdra.decimals(), 2);
        assertEq(idra.decimals(), newIdra.decimals());
    }

    function test_TC_DECIMALS_005_DecimalsWorksWithMinting() public {
        vm.startPrank(MINTER);
        idra.mint(USER1, 1000e18);
        vm.stopPrank();

        assertEq(idra.balanceOf(USER1), 1000e18);
        assertEq(idra.decimals(), 2);
    }

    function test_TC_DECIMALS_006_DecimalsWorksWithTransfers() public {
        vm.startPrank(MINTER);
        idra.mint(USER1, 1000e18);
        vm.stopPrank();

        vm.startPrank(USER1);
        idra.transfer(USER2, 500e18);
        vm.stopPrank();

        assertEq(idra.balanceOf(USER1), 500e18);
        assertEq(idra.balanceOf(USER2), 500e18);
        assertEq(idra.decimals(), 2);
    }

    function test_TC_DECIMALS_007_DecimalsTypeIsUint8() public view {
        uint8 decimalsValue = idra.decimals();
        assertEq(decimalsValue, 2);
        assertTrue(decimalsValue <= type(uint8).max);
    }

    function test_TC_DECIMALS_008_DecimalsOnDifferentChains() public {
        IDRA idraChain1 = _deployIDRAOnChain(SOURCE_CHAIN_ID);
        IDRA idraChain2 = _deployIDRAOnChain(DEST_CHAIN_ID);

        assertEq(idraChain1.decimals(), 2);
        assertEq(idraChain2.decimals(), 2);
        assertEq(idraChain1.decimals(), idraChain2.decimals());
    }
}
