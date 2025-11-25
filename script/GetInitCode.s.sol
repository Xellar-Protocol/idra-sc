// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/IDRA.sol";

contract GetInitCode is Script, Config {
    function run() external {
        // Load config for role addresses
        _loadConfig("./deployments.toml", false);

        // Implementation address from env or config
        address implementation = vm.envOr(
            "IMPLEMENTATION",
            config.get("implementation").toAddress()
        );
        require(implementation != address(0), "IMPLEMENTATION missing");

        // Token metadata from env (defaults for IDRA project)
        string memory name = vm.envOr("TOKEN_NAME", string("IDRA"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("IDRA"));

        // Role addresses from config (can be overridden via env if desired)
        address defaultAdmin = config.get("default-admin").toAddress();
        address minter = config.get("default-minter").toAddress();
        address burner = config.get("default-burner").toAddress();
        address pauser = config.get("default-pauser").toAddress();
        address blacklister = config.get("default-blacklister").toAddress();

        require(defaultAdmin != address(0), "default-admin missing");
        require(minter != address(0), "default-minter missing");
        require(pauser != address(0), "default-pauser missing");
        require(blacklister != address(0), "default-blacklister missing");

        // Build initialization calldata specific to IDRA
        bytes memory initData = abi.encodeWithSelector(
            IDRA.initialize.selector,
            name,
            symbol,
            defaultAdmin,
            minter,
            burner,
            pauser,
            blacklister
        );

        // Construct init code for ERC1967Proxy(implementation, initData)
        bytes memory initCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        // Output
        console2.log("Implementation:", implementation);
        console2.log("Name:", name);
        console2.log("Symbol:", symbol);
        console2.log("Admin:", defaultAdmin);
        console2.log("Minter:", minter);
        console2.log("Burner:", burner);
        console2.log("Pauser:", pauser);
        console2.log("Blacklister:", blacklister);
        console2.log("Init data length:", initData.length);
        console2.logBytes(initData);
        console2.log("Init code length:", initCode.length);
        console2.logBytes(initCode);
        console2.log("keccak256(initCode):");
        console2.logBytes32(keccak256(initCode));
    }
}
