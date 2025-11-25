// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Config} from "forge-std/Config.sol";
import {IDRA} from "../src/IDRA.sol";

contract GetAllRoles is Script, Config {
    function run() public {
        _loadConfig("./deployments.toml", false);

        address idraAddress = config.get("proxy").toAddress();
        IDRA idra = IDRA(payable(idraAddress));

        console.log("\n=== ROLE MEMBERS (chain)");
        console.log("Proxy:", idraAddress);
        console.log("ChainId:", block.chainid);

        _printRoleMembers(
            "DEFAULT_ADMIN_ROLE",
            idra.DEFAULT_ADMIN_ROLE(),
            idra
        );
        _printRoleMembers("MINTER_ROLE", idra.MINTER_ROLE(), idra);
        _printRoleMembers("PAUSER_ROLE", idra.PAUSER_ROLE(), idra);
        _printRoleMembers("BURNER_ROLE", idra.BURNER_ROLE(), idra);
        _printRoleMembers("BLACKLISTER_ROLE", idra.BLACKLISTER_ROLE(), idra);
        _printRoleMembers("UPGRADER_ROLE", idra.UPGRADER_ROLE(), idra);
        _printRoleMembers("BRIDGE_ROLE", idra.BRIDGE_ROLE(), idra);

        // Fees overview
        console.log("\n=== FEES");
        console.log("Fee collector:", idra.feeCollector());
        // Optionally show fee for a specific destination chain if provided via env
        uint256 fee = idra.getBridgeFee();
        console.log("Bridge fee: ", fee);
    }

    function _printRoleMembers(
        string memory name,
        bytes32 role,
        IDRA idra
    ) internal view {
        address[] memory members = idra.getRoleMembers(role);
        console.log(
            string(abi.encodePacked("\n", name, " (", members.length, "):"))
        );
        if (members.length == 0) {
            console.log("<none>");
            return;
        }
        for (uint256 i = 0; i < members.length; i++) {
            console.log(members[i]);
        }
    }
}
