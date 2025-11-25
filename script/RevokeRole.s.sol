// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Config} from "forge-std/Config.sol";
import "../src/IDRA.sol";

contract RevokeRole is Script, Config {
    function run() external {
        // Load proxy from deployments.toml (same pattern as GetAllRoles.s.sol)
        _loadConfig("./deployments.toml", false);
        address proxyAddr = config.get("proxy").toAddress();

        // Role and account come from env for run()
        string memory roleName = vm.envOr("ROLE_NAME", string(""));
        address account = vm.envOr("ACCOUNT", address(0));

        require(proxyAddr != address(0), "proxy missing in config");
        require(bytes(roleName).length != 0, "ROLE_NAME env required");
        require(account != address(0), "ACCOUNT env required");

        vm.startBroadcast();
        IDRA idra = IDRA(payable(proxyAddr));
        idra.revokeRole(_roleHash(idra, roleName), account);
        vm.stopBroadcast();

        console.log("Revoked", roleName, "from", account);
    }

    // Preferred CLI usage:
    // forge script script/RevokeRole.s.sol:RevokeRole --sig "revoke(address,string,address)" <proxy> <role> <account> --private-key $KEY --broadcast
    function revoke(
        address proxyAddr,
        string memory roleName,
        address account
    ) external {
        require(proxyAddr != address(0), "proxy required");
        require(bytes(roleName).length != 0, "role required");
        require(account != address(0), "account required");

        vm.startBroadcast();
        IDRA idra = IDRA(payable(proxyAddr));
        idra.revokeRole(_roleHash(idra, roleName), account);
        vm.stopBroadcast();

        console.log("Revoked", roleName, "from", account);
    }

    function _roleHash(
        IDRA idra,
        string memory roleName
    ) internal view returns (bytes32) {
        if (_eq(roleName, "DEFAULT_ADMIN_ROLE"))
            return idra.DEFAULT_ADMIN_ROLE();
        if (_eq(roleName, "MINTER_ROLE")) return idra.MINTER_ROLE();
        if (_eq(roleName, "PAUSER_ROLE")) return idra.PAUSER_ROLE();
        if (_eq(roleName, "BLACKLISTER_ROLE")) return idra.BLACKLISTER_ROLE();
        if (_eq(roleName, "UPGRADER_ROLE")) return idra.UPGRADER_ROLE();
        if (_eq(roleName, "BRIDGE_ROLE")) return idra.BRIDGE_ROLE();
        revert("unknown role");
    }

    function _eq(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
