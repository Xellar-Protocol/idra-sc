// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library IDRALib {
    /**
     * @dev Compute a unique bridge identifier from source/destination parameters.
     * Keeping this logic in a library ensures both request and completion use identical hashing.
     */
    function computeBridgeId(
        address from,
        uint256 destinationChainId,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 sourceChainId
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    from,
                    destinationChainId,
                    to,
                    amount,
                    nonce,
                    sourceChainId
                )
            );
    }
}
