// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity ^0.8.27;

import { Context } from "../libs/VM.sol";
import { Opcode } from "../libs/OpcodeList.sol";
import { MemoryPtr, MemoryPtrLib } from "../libs/MemoryPtr.sol";
import { InstructionBuilder } from "../libs/InstructionBuilder.sol";
import { InstructionArgs } from "../libs/InstructionArgs.sol";

interface IPercolateVerifier {
    function verifyAndConsume(address taker, bytes calldata journalBytes, bytes calldata seal) external;
}

library PercolateGate {
    using InstructionArgs for bytes;
    using InstructionBuilder for MemoryPtr;

    Opcode constant opcode = Opcode.PercolateGate;

    // Journal Percolate: abi.encode(bytes32,bytes32,address,uint64) = 4 x 32-byte word, fixed length
    uint256 constant JOURNAL_LENGTH = 128;
    // Seal Groth16 RISC Zero: 4-byte verifier selector + abi.encode(Seal{a,b,c}) = 4 + 256 = 260 byte.
    // Confirmed from RiscZeroGroth16Verifier._verifyIntegrity() in risc0-ethereum:
    // seal[:4] = selector, seal[4:] = abi.decode(_, (Seal)), Seal just contains fixed-size array
    // (uint256[2] a, uint256[2][2] b, uint256[2] c) so ABI encoding is static, no dynamic offset
    uint256 constant SEAL_LENGTH = 260;

    function sizeOf(address) internal pure returns (uint256) {
        return InstructionBuilder.sizeOf() + 20;
    }

    function build(address verifier) internal pure returns (bytes memory) {
        return build(MemoryPtrLib.alloc(sizeOf(verifier)), verifier).resolve();
    }

    function build(MemoryPtr ptrStart, address verifier) internal pure returns (MemoryPtr ptr) {
        ptr = ptrStart.pushHeader(opcode);
        ptr = ptr.push(verifier);
        ptrStart.patchLength(ptr);
    }

    function parse(bytes calldata args) internal pure returns (address verifier) {
        verifier = args.at(0).asAddress();
    }

    function exec(Context memory ctx, bytes calldata args) internal {
        address verifier = parse(args);

        bytes calldata journalBytes = ctx.tryChopTakerArgs(JOURNAL_LENGTH);
        bytes calldata seal = ctx.tryChopTakerArgs(SEAL_LENGTH);

        IPercolateVerifier(verifier).verifyAndConsume(ctx.query.taker, journalBytes, seal);
    }
}
