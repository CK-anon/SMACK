// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Library for managing a uint8 to bool mapping in a compact way.
 * Essentially a modified version of OpenZeppelin's BitMaps contract.
 */
library SingleSlotBitArray {
    /**
     * @dev A single uint256 that contains all bits of storage.
     */
    struct BitArray256 {
        uint256 storedValue;
    }

    /**
     * @dev Returns whether the bit at `index` is set.
     */
    function get(BitArray256 storage bitArray, uint8 index) internal view returns (bool) {
        uint256 mask = 1 << (index & 0xff);
        return bitArray.storedValue & mask != 0;
    }
    
    /**
     * @dev Sets the bit at `index` to the boolean `value`.
     */
    function set(BitArray256 storage bitArray, uint8 index, bool value) internal {
        uint256 mask = 1 << (index & 0xff);
        if (value) {
            // Set the bit
            bitArray.storedValue |= mask;
        } else {
            // Unset the bit
            bitArray.storedValue &= ~mask;
        }
    }
}
