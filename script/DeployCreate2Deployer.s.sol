// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Create2Deployer.sol";

contract DeployCreate2Deployer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint(
            "IDRA_FACTORY_DEPLOYER_PRIVATE_KEY"
        );
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the CREATE2 helper factory
        Create2Deployer deployer = new Create2Deployer();
        console.log("DEPLOYED TO:");
        console.log(address(deployer));
        vm.stopBroadcast();
    }
}
