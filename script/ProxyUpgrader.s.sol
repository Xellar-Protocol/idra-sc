// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Config} from "forge-std/Config.sol";
import "../src/IDRA.sol";

interface IUUPSUpgradeableMinimal {
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract ProxyUpgrader is Script, Config {
    function run() external {
        // Load config (network inferred from RPC via Config)
        _loadConfig("./deployments.toml", false);

        // Addresses from config
        address proxy = config.get("proxy").toAddress();
        address configuredImpl = config.get("implementation").toAddress();
        require(proxy != address(0), "proxy missing");

        // Allow override of new implementation via env NEW_IMPL
        address newImplementation = vm.envOr("NEW_IMPL", configuredImpl);
        require(newImplementation != address(0), "new impl missing");

        // Optional: sanity call to read current version via proxy before upgrade
        string memory beforeVersion = "";
        try IDRA(proxy).version() returns (string memory v) {
            beforeVersion = v;
        } catch {}

        vm.startBroadcast();

        // Perform UUPS upgrade (caller must have UPGRADER_ROLE on proxy)
        IUUPSUpgradeableMinimal(proxy).upgradeToAndCall(newImplementation, "");

        vm.stopBroadcast();

        // Optional: read version after upgrade
        string memory afterVersion = "";
        try IDRA(proxy).version() returns (string memory v2) {
            afterVersion = v2;
        } catch {}

        console2.log("Proxy upgraded");
        console2.log("Proxy:", proxy);
        console2.log("New implementation:", newImplementation);
        if (
            bytes(beforeVersion).length != 0 || bytes(afterVersion).length != 0
        ) {
            console2.log("Version before:", beforeVersion);
            console2.log("Version after:", afterVersion);
        }
    }
}
