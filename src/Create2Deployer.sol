// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Create2Deployer
 * @dev Minimal helper factory for CREATE2 deployments.
 * - Provides address prediction helpers to derive the deployed address off-chain/on-chain
 * - Supports deployments with and without attached ETH value
 */
contract Create2Deployer {
    /// @dev Emitted when a new contract is deployed by this factory using CREATE2
    event Deployed(address indexed deployedAddress, bytes32 indexed salt);

    /**
     * @dev Deploy a contract using CREATE2 without sending ETH
     * @param salt User-provided salt controlling the resulting address
     * @param bytecode Creation bytecode of the contract to deploy
     * @return deployedAddress Address of the deployed contract
     */
    function deploy(
        bytes32 salt,
        bytes memory bytecode
    ) external returns (address deployedAddress) {
        if (bytecode.length == 0) revert("EMPTY_BYTECODE");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            let encoded_data := add(bytecode, 0x20)
            let encoded_size := mload(bytecode)
            deployedAddress := create2(0, encoded_data, encoded_size, salt)
        }
        require(deployedAddress != address(0), "CREATE2_DEPLOY_FAILED");

        emit Deployed(deployedAddress, salt);
    }

    /**
     * @dev Deploy a contract using CREATE2 sending exactly `value` wei
     * @param salt User-provided salt controlling the resulting address
     * @param bytecode Creation bytecode of the contract to deploy
     * @param value ETH value to forward to the constructor
     * @return deployedAddress Address of the deployed contract
     */
    function deployWithValue(
        bytes32 salt,
        bytes memory bytecode,
        uint256 value
    ) external payable returns (address deployedAddress) {
        if (bytecode.length == 0) revert("EMPTY_BYTECODE");
        require(msg.value == value, "INCORRECT_MSG_VALUE");

        // solhint-disable-next-line no-inline-assembly
        assembly {
            let encoded_data := add(bytecode, 0x20)
            let encoded_size := mload(bytecode)
            deployedAddress := create2(value, encoded_data, encoded_size, salt)
        }
        require(deployedAddress != address(0), "CREATE2_DEPLOY_FAILED");

        emit Deployed(deployedAddress, salt);
    }

    /**
     * @dev Predict the address for a given salt and bytecode hash deployed by this factory
     * @param salt Salt used for deployment
     * @param bytecodeHash keccak256 of the contract creation bytecode
     */
    function computeAddress(
        bytes32 salt,
        bytes32 bytecodeHash
    ) public view returns (address) {
        return computeAddressFor(salt, bytecodeHash, address(this));
    }

    /**
     * @dev Predict the address for a given salt and bytecode hash for an arbitrary deployer
     * @param salt Salt used for deployment
     * @param bytecodeHash keccak256 of the contract creation bytecode
     * @param deployer Address of the CREATE2 deployer (factory)
     */
    function computeAddressFor(
        bytes32 salt,
        bytes32 bytecodeHash,
        address deployer
    ) public pure returns (address) {
        // Address derivation per EIP-1014
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash)
        );
        return address(uint160(uint256(hash)));
    }

    /**
     * @dev Convenience helper to compute keccak256(bytecode)
     * @param bytecode Creation bytecode of the contract to deploy
     */
    function bytecodeHash(bytes memory bytecode) public pure returns (bytes32) {
        return keccak256(bytecode);
    }
}
