// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ISwapVM } from "./interfaces/ISwapVM.sol";
import { MakerTraitsLib, MakerTraits } from "./libs/MakerTraits.sol";
import { StaticBalances } from "./instructions/Balances.sol";
import { LimitSwap } from "./instructions/LimitSwap.sol";
import { PercolateGate } from "./instructions/PercolateGate.sol";
import { TakerTraitsLib } from "./libs/TakerTraits.sol";

contract OrderBuilderHelper {
    function buildOrder(
        address maker,
        address tokenA,
        address tokenB,
        uint256 reserveA,
        uint256 reserveB,
        address percolateVerifier
    ) external pure returns (address orderMaker, uint256 traits, bytes memory data) {
        bytes memory program = bytes.concat(
            StaticBalances.build(reserveA, reserveB),
            LimitSwap.build(tokenA, tokenB),
            PercolateGate.build(percolateVerifier)
        );

        ISwapVM.Order memory order = MakerTraitsLib.build(MakerTraitsLib.Args({
            maker: maker,
            tokenA: tokenA,
            tokenB: tokenB,
            shouldUnwrapWeth: false,
            useAquaInsteadOfSignature: false,
            allowZeroAmountIn: false,
            receiver: address(0),
            hasPreTransferInHook: false,
            hasPostTransferInHook: false,
            hasPreTransferOutHook: false,
            hasPostTransferOutHook: false,
            preTransferInTarget: address(0),
            preTransferInData: "",
            postTransferInTarget: address(0),
            postTransferInData: "",
            preTransferOutTarget: address(0),
            postTransferOutData: "",
            postTransferOutTarget: address(0),
            preTransferOutData: "",
            program: program
        }));

        return (order.maker, MakerTraits.unwrap(order.traits), order.data);
    }

    function buildTakerData(
        address taker,
        bool isAToB,
        bytes calldata journalBytes,
        bytes calldata seal,
        bytes calldata signature
    ) external pure returns (bytes memory) {
        return TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: address(0),
            isExactIn: true,
            shouldUnwrapWeth: false,
            isStrictThresholdAmount: false,
            isFirstTransferFromTaker: false,
            useTransferFromAndAquaPush: false,
            isAToB: isAToB,
            allowPartialFill: false,
            threshold: "",
            to: taker,
            deadline: 0,
            hasPreTransferInCallback: false,
            hasPreTransferOutCallback: false,
            preTransferInHookData: "",
            postTransferInHookData: "",
            preTransferOutHookData: "",
            postTransferOutHookData: "",
            preTransferInCallbackData: "",
            preTransferOutCallbackData: "",
            instructionsArgs: bytes.concat(journalBytes, seal),
            signature: signature
        }));
    }
}
