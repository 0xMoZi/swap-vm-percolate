// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { TokenMock } from "@1inch/solidity-utils/contracts/mocks/TokenMock.sol";

import { ISwapVM } from "../../contracts/interfaces/ISwapVM.sol";
import { LimitSwapVMRouter } from "../../contracts/routers/LimitSwapVMRouter.sol";
import { MakerTraitsLib } from "../../contracts/libs/MakerTraits.sol";
import { TakerTraitsLib } from "../../contracts/libs/TakerTraits.sol";
import { StaticBalances } from "../../contracts/instructions/Balances.sol";
import { LimitSwap } from "../../contracts/instructions/LimitSwap.sol";
import { PercolateGate } from "../../contracts/instructions/PercolateGate.sol";

interface IPercolateVerifierAdmin {
    function setRoot(bytes32 newRoot) external;
    function currentRoot() external view returns (bytes32);
}

contract PercolateGateIntegrationTest is Test {
    LimitSwapVMRouter constant swapVM = LimitSwapVMRouter(payable(0xFC5E565420013D413D55e6cAc1a7F46806c122C6));
    IPercolateVerifierAdmin constant percolate = IPercolateVerifierAdmin(0xA07bAbf043E2fF2D0Aa671e387bd6D6b000efC8D);
    address constant RISC_ZERO_ROUTER = 0x925d8331ddc0a1F0d96E68CF073DFE1d92b69187;
    address constant REAL_MAKER = 0xC949D76e078a397d24607989A9eB1369c6e738aC;

    TokenMock tokenA;
    TokenMock tokenB;

    address maker;
    uint256 makerPK = 0x1234;
    address taker = address(0xBEEF);

    function setUp() public {
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        maker = vm.addr(makerPK);

        tokenA = new TokenMock("Token I", "TKI");
        tokenB = new TokenMock("Token J", "TKJ");
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);

        tokenA.mint(maker, 1e24);
        tokenB.mint(maker, 1e24);
        tokenA.mint(taker, 1e24);
        tokenB.mint(taker, 1e24);

        vm.prank(maker);
        tokenA.approve(address(swapVM), type(uint256).max);
        vm.prank(maker);
        tokenB.approve(address(swapVM), type(uint256).max);
        vm.prank(taker);
        tokenA.approve(address(swapVM), type(uint256).max);
        vm.prank(taker);
        tokenB.approve(address(swapVM), type(uint256).max);
    }

    function _buildJournal(bytes32 root, address callerBinding, bytes32 nullifier) internal view returns (bytes memory) {
        return abi.encode(nullifier, root, callerBinding, uint64(block.timestamp + 1 hours));
    }

    function _mockVerifySucceeds(bytes memory seal, bytes memory journalBytes) internal {
        bytes32 imageId = 0xcb34c8c6725243346c9306c6c319fe87f21addce825b188c6f9e974e569acd69;
        vm.mockCall(
            RISC_ZERO_ROUTER,
            abi.encodeWithSignature("verify(bytes,bytes32,bytes32)", seal, imageId, sha256(journalBytes)),
            ""
        );
    }

    function test_swap_succeedsWithValidProof() public {
        bytes32 root = keccak256("demo-root");
        vm.prank(REAL_MAKER);
        percolate.setRoot(root);

        bytes32 nullifier = keccak256("nullifier-1");
        bytes memory journalBytes = _buildJournal(root, taker, nullifier);
        bytes memory seal = new bytes(260);
        _mockVerifySucceeds(seal, journalBytes);

        ISwapVM.Order memory order = MakerTraitsLib.build(MakerTraitsLib.Args({
            maker: maker,
            tokenA: address(tokenA),
            tokenB: address(tokenB),
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
            program: bytes.concat(
                StaticBalances.build(100e18, 200e18),
                LimitSwap.build(address(tokenA), address(tokenB)),
                PercolateGate.build(address(percolate))
            )
        }));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPK, swapVM.hash(order));
        bytes memory takerData = TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: address(0),
            isExactIn: true,
            shouldUnwrapWeth: false,
            isStrictThresholdAmount: false,
            isFirstTransferFromTaker: false,
            useTransferFromAndAquaPush: false,
            isAToB: true,
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
            signature: abi.encodePacked(r, s, v)
        }));

        vm.prank(taker);
        (uint256 amountIn, uint256 amountOut,) = swapVM.swap(order, 100e18, takerData);

        assertEq(amountIn, 100e18);
        assertEq(amountOut, 200e18);
    }

    function test_swap_revertsOnRootMismatch() public {
        bytes32 wrongRoot = keccak256("stale-root");
        bytes32 currentRoot = keccak256("current-root");
        vm.prank(REAL_MAKER);
        percolate.setRoot(currentRoot);

        bytes memory journalBytes = _buildJournal(wrongRoot, taker, keccak256("nullifier-2"));
        bytes memory seal = new bytes(260);

        ISwapVM.Order memory order = MakerTraitsLib.build(MakerTraitsLib.Args({
            maker: maker,
            tokenA: address(tokenA),
            tokenB: address(tokenB),
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
            program: bytes.concat(
                StaticBalances.build(100e18, 200e18),
                LimitSwap.build(address(tokenA), address(tokenB)),
                PercolateGate.build(address(percolate))
            )
        }));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPK, swapVM.hash(order));
        bytes memory takerData = TakerTraitsLib.build(TakerTraitsLib.Args({
            taker: address(0),
            isExactIn: true,
            shouldUnwrapWeth: false,
            isStrictThresholdAmount: false,
            isFirstTransferFromTaker: false,
            useTransferFromAndAquaPush: false,
            isAToB: true,
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
            signature: abi.encodePacked(r, s, v)
        }));

        vm.prank(taker);
        vm.expectRevert(); // PercolateVerifier.RootMismatch - not caller a router yet
        swapVM.swap(order, 100e18, takerData);
    }
}
