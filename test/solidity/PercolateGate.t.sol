// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { PercolateGate, IPercolateVerifier } from "../../contracts/instructions/PercolateGate.sol";

contract MockPercolateVerifier is IPercolateVerifier {
    address public lastTaker;
    bytes public lastJournal;
    bytes public lastSeal;

    function verifyAndConsume(address taker, bytes calldata journalBytes, bytes calldata seal) external override {
        lastTaker = taker;
        lastJournal = journalBytes;
        lastSeal = seal;
    }
}

contract PercolateGateTest is Test {
    function test_build_encodesVerifierAddress() public pure {
        address verifier = address(0xBEEF);
        bytes memory encoded = PercolateGate.build(verifier);
        assertEq(encoded.length, 2 + 20);
    }
}
