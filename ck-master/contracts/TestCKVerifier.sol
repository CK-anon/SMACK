// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev A contract that attests to proofs of complete knowledge
 */
interface ICKVerifier {
    /**
     * @dev Returns true if the address has shown a proof of complete knowledge
     * to this verifier.
     */
    function isCKVerified(address addr) external returns (bool);
}

/**
 * @dev A permissioned contract following the ICKVerifier specification
 * that can be used for testing.
 */
contract TestCKVerifier is ICKVerifier, Ownable {
    mapping (address => bool) public isCKVerified;
    
    function setCKVerified(address addr, bool verified) public onlyOwner {
    	isCKVerified[addr] = verified;
    }
}
