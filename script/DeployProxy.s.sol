// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import "../src/Create2Deployer.sol";
import "../src/IDRA.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ProxyDeployer is Script, Config {
    function run() external {
        // Load config (network-specific section inferred from RPC via Config)
        _loadConfig("./deployments.toml", false);

        // Required addresses from config
        address create2Factory = config.get("create-2-deployer").toAddress();
        address implementation = config.get("implementation").toAddress();
        address defaultAdmin = config.get("default-admin").toAddress();
        address minter = config.get("default-minter").toAddress();
        address burner = config.get("default-burner").toAddress();
        address pauser = config.get("default-pauser").toAddress();
        address blacklister = config.get("default-blacklister").toAddress();

        require(create2Factory != address(0), "create2 factory missing");
        require(implementation != address(0), "implementation missing");
        require(defaultAdmin != address(0), "default-admin missing");
        require(minter != address(0), "default-minter missing");
        require(burner != address(0), "default-burner missing");
        require(pauser != address(0), "default-pauser missing");
        require(blacklister != address(0), "default-blacklister missing");

        // Token metadata from env (with sane defaults)
        string memory name = vm.envOr("TOKEN_NAME", string("IDRA"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("IDRA"));

        // CREATE2 salt from env
        bytes32 proxySalt = config.get("proxy-v1-salt").toBytes32();
        require(proxySalt != bytes32(0), "proxy-v1-salt required");

        console.log("Proxy deploy information:");
        console.log("Create2 factory:", create2Factory);
        console.log("Implementation:", implementation);
        console.log("Default admin:", defaultAdmin);
        console.log("Minter:", minter);
        console.log("Burner:", burner);
        console.log("Pauser:", pauser);
        console.log("Blacklister:", blacklister);
        console.log("Proxy salt:");

        // Build initialization calldata for proxy
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

        vm.startBroadcast();

        // Construct proxy creation bytecode with init data
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );

        // Deploy proxy via CREATE2 factory
        address proxy = Create2Deployer(create2Factory).deploy(
            proxySalt,
            proxyBytecode
        );

        vm.stopBroadcast();

        // Log results
        console2.log("IDRA proxy:", proxy);
    }
}
