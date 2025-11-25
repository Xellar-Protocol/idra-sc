// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import "../src/Create2Deployer.sol";
import "../src/IDRA.sol";

contract DeployIDRA is Script, Config {
    function run() external {
        // Load config (network-specific section inferred from RPC via Config)
        _loadConfig("./deployments.toml", false);

        // Required addresses from config
        address create2Factory = config.get("create-2-deployer").toAddress();
        require(create2Factory != address(0), "create2 factory missing");

        // CREATE2 salt from env
        bytes32 implSalt = config.get("impl-v1-salt").toBytes32();
        require(implSalt != bytes32(0), "IMPL_SALT required");

        console.log("Deploy information:");
        console.log("Create2 factory:", create2Factory);
        console.log("Impl salt:");
        console.logBytes32(implSalt);

        // Build creation bytecode for implementation
        bytes memory idraBytecode = type(IDRA).creationCode;

        vm.startBroadcast();

        // Deploy implementation via CREATE2 factory
        address implementation = Create2Deployer(create2Factory).deploy(
            implSalt,
            idraBytecode
        );

        vm.stopBroadcast();

        // Log results
        console2.log("IDRA implementation:", implementation);
    }
}
