// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BaseCode} from "./BaseAutomators.t.sol";

//V3Utils
import "../../../src/transformers/V3Utils.sol";
import "../../../src/utils/Constants.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import{MockToken} from "../mocks/MockToken.sol";


contract V3UtilsKTest is BaseCode {


// ============================================
// ==                V3Utils                 ==
// ============================================

    function testFuzz_UnauthorizedTransfer(
        address testNftAccount, 
        uint256 testNft
    ) external {
        // Asegurar que el testNftAccount no sea la dirección cero
        vm.assume(testNftAccount != address(0));

        // Asumir que el testNftAccount tiene al menos un NFT para la prueba
        uint256 initialBalance = NPM.balanceOf(testNftAccount);
        // vm.assume(initialBalance > 0);

        // Detallar los parámetros del struct Instructions
        V3Utils.Instructions memory inst = V3Utils.Instructions(
            V3Utils.WhatToDo.CHANGE_RANGE,
            address(0),
            0,
            0,
            0,
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            testNftAccount,
            testNftAccount,
            false,
            "",
            ""
        );

        // Codificar los parámetros para la llamada de bajo nivel
        bytes memory data = abi.encodeWithSignature(
            "safeTransferFrom(address,address,uint256,bytes)",
            testNftAccount,
            address(v3utils),
            testNft,
            abi.encode(inst)
        );

        // Configurar la expectativa de revert
        vm.expectRevert(abi.encodePacked("ERC721: transfer caller is not owner nor approved"));

        // Realizar la llamada de bajo nivel
        (bool success, bytes memory returnData) = address(NPM).call(data);
        require(!success, "Transfer should have failed");

        // Verificar el balance final
        uint256 finalBalance = NPM.balanceOf(testNftAccount);
        console.log("Initial Balance of testNftAccount:", initialBalance);
        console.log("Final Balance of testNftAccount:", finalBalance);

        // Asegurarse de que el balance inicial y final sean iguales
        assertEq(initialBalance, finalBalance, "Balance of testNftAccount should remain unchanged");
    }


    function testFuzz_UnauthorizedTransferParam(
        uint256 amountIn0,
        uint256 amountIn1,
        uint128 feeAmount0,
        uint128 feeAmount1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external {
        // Create Instructions struct with specified values
        V3Utils.Instructions memory inst = V3Utils.Instructions(
            V3Utils.WhatToDo.CHANGE_RANGE,
            address(0),
            0, 
            0, 
            amountIn0,
            0,
            "",
            amountIn1,
            0, 
            "", 
            feeAmount0,
            feeAmount1,
            fee,
            tickLower,
            tickUpper,
            liquidity,
            0, 
            0, 
            block.timestamp + 1 hours,
            TEST_NFT_ACCOUNT,
            TEST_NFT_ACCOUNT,
            false,
            "",
            ""
        );

        // Encode the function call for safeTransferFrom
        bytes memory transferData = abi.encodeWithSignature(
            "safeTransferFrom(address,address,uint256,bytes)",
            TEST_NFT_ACCOUNT,
            address(v3utils),
            TEST_NFT,
            abi.encode(inst)
        );

        // Expect revert with "ERC721: transfer caller is not owner nor approved"
        vm.expectRevert(abi.encodePacked("ERC721: transfer caller is not owner nor approved"));
        
        // Perform the low-level call to safeTransferFrom
        (bool success, bytes memory returnData) = address(NPM).call(transferData);
        assert(!success);
    }

    function testFuzzInvalidInstructions(
        bool param1,
        bool param2,
        uint256 param3,
        string memory param4
    ) external {
        // Encode invalid instructions data
        bytes memory invalidInstructionsData = abi.encode(param1, param2, param3, param4);

        // Encode the function call for safeTransferFrom
        bytes memory transferData = abi.encodeWithSignature(
            "safeTransferFrom(address,address,uint256,bytes)",
            TEST_NFT_ACCOUNT,
            address(v3utils),
            TEST_NFT,
            invalidInstructionsData
        );

        // Expect revert with "ERC721: transfer to non ERC721Receiver implementer"
        vm.expectRevert(abi.encodePacked("ERC721: transfer to non ERC721Receiver implementer"));
        
        // Perform the low-level call to safeTransferFrom
        vm.prank(TEST_NFT_ACCOUNT);
        (bool success, bytes memory returnData) = address(NPM).call(transferData);
        assert(!success);
    }


    function testFuzzSendEtherNotAllowed(uint256 amount) external {
        // Ensure the amount is within a reasonable range and not zero
        vm.assume(amount > 0); // Assuming 1 ETH max for testing

        // Expect revert with NotWETH
        vm.expectRevert();

        // Perform the low-level call to send ether
        (bool success, ) = address(v3utils).call{value: amount}("");
    }

    function testFuzzFailEmptySwapAndIncreaseLiquidity(
        uint256 amount0Desired
    ) external {
        amount0Desired = bound(amount0Desired, 1, (type(uint256).max) /3);

        V3Utils.SwapAndIncreaseLiquidityParams memory params = V3Utils.SwapAndIncreaseLiquidityParams(
            TEST_NFT,
            amount0Desired, // Bound fuzz parameter
            0,
            TEST_NFT_ACCOUNT,
            block.timestamp,
            IERC20(address(0)),
            0,
            0,
            "",
            0,
            0,
            "",
            0,
            0,
            ""
        );

        // Encode the function call
        bytes memory data = abi.encodeWithSignature(
            "swapAndIncreaseLiquidity((uint256,uint256,uint256,address,uint256,address,uint256,uint256,bytes,uint256,uint256,bytes,uint256,uint256,bytes))",
            params
        );

        // Perform the low-level call
        vm.prank(TEST_NFT_ACCOUNT);
        (bool success, ) = address(v3utils).call(data);

        // The call should fail
        // assert(!success);
    }


    // function testFuzzTransferDecreaseSlippageError( 
    //     uint128 liquidityBefore,
    //     uint256 amountRemoveMin0,
    //     uint256 amountRemoveMin1,
    //     uint256 amountIn0,
    //     uint256 amountIn1,
    //     uint256 amountOut0Min,
    //     uint256 amountOut1Min,
    //     uint128 feeAmount0,
    //     uint128 feeAmount1,
    //     uint24 fee,
    //     int24 tickLower,
    //     int24 tickUpper,
    //     uint256 amountAddMin0,
    //     uint256 amountAddMin1,
    //     uint256 deadline
    // ) external { //@audit => reduce 
    //     // Bound the parameters to ensure they are within a reasonable range
    //     amountRemoveMin0 = bound(amountRemoveMin0, 1, type(uint256).max);
    //     amountRemoveMin1 = bound(amountRemoveMin1, 1, type(uint256).max);
    //     amountIn0 = bound(amountIn0, 1, type(uint256).max);
    //     amountIn1 = bound(amountIn1, 1, type(uint256).max);
    //     amountOut0Min = bound(amountOut0Min, 1, type(uint256).max);
    //     amountOut1Min = bound(amountOut1Min, 1, type(uint256).max);
    //     feeAmount0 = uint128(bound(uint256(feeAmount0), 1, uint256(type(uint128).max)));
    //     feeAmount1 = uint128(bound(uint256(feeAmount1), 1, uint256(type(uint128).max)));
    //     amountAddMin0 = bound(amountAddMin0, 1, type(uint256).max);
    //     amountAddMin1 = bound(amountAddMin1, 1, type(uint256).max);
    //     deadline = bound(deadline, block.timestamp + 1, type(uint256).max);

    //     // Assume conditions for tickLower and tickUpper to avoid conversion issues
    //     vm.assume(tickLower >= type(int24).min && tickLower < type(int24).max);
    //     vm.assume(tickUpper > tickLower && tickUpper <= type(int24).max);

    //     // Add liquidity to the existing (empty) position
    //     _increaseLiquidity();

    //     // Mock the positions call to return the specified liquidity
    //     // vm.mockCall(
    //     //     address(NPM),
    //     //     abi.encodeWithSelector(INonfungiblePositionManager(NPM).positions.selector, TEST_NFT),
    //     //     abi.encode(0, 0, 0, 0, 0, 0, 0, 0, liquidityBefore, 0, 0, 0, 0)
    //     // );

    //     // Create Instructions struct with specified values
    //     V3Utils.Instructions memory inst = V3Utils.Instructions(
    //         V3Utils.WhatToDo.CHANGE_RANGE,
    //         address(usdc),
    //         amountRemoveMin0,
    //         amountRemoveMin1,
    //         amountIn0,
    //         amountOut0Min,
    //         _get05DAIToUSDCSwapData(),
    //         amountIn1,
    //         amountOut1Min,
    //         "", // swapData1
    //         feeAmount0,
    //         feeAmount1,
    //         fee,
    //         tickLower,
    //         tickUpper,
    //         liquidityBefore,
    //         amountAddMin0,
    //         amountAddMin1,
    //         deadline,
    //         TEST_NFT_ACCOUNT,
    //         TEST_NFT_ACCOUNT,
    //         false,
    //         "",
    //         ""
    //     );

    //     // Encode the function call for safeTransferFrom
    //     bytes memory transferData = abi.encodeWithSignature(
    //         "safeTransferFrom(address,address,uint256,bytes)",
    //         TEST_NFT_ACCOUNT,
    //         address(v3utils),
    //         TEST_NFT,
    //         abi.encode(inst)
    //     );

    //     // Expect revert with "Price slippage check"
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     vm.expectRevert("Price slippage check");
        
    //     // Perform the low-level call to safeTransferFrom
    //     (bool success, bytes memory returnData) = address(NPM).call(transferData);
    //     assert(!success);
    // }

    // function testFuzzTransferDecreaseSlippageError_LiquidityRemoval(
    //     uint128 liquidityBefore,
    //     uint256 amountRemoveMin0,
    //     uint256 amountRemoveMin1
    // ) external { //@audit => invalid token ID
    //     // Bound the parameters to ensure they are within a reasonable range
    //     amountRemoveMin0 = bound(amountRemoveMin0, 1, type(uint256).max);
    //     amountRemoveMin1 = bound(amountRemoveMin1, 1, type(uint256).max);

    //     // Add liquidity to the existing (empty) position
    //     _increaseLiquidity();

    //     // Mock the positions call to return the specified liquidity
    //     // vm.mockCall(
    //     //     address(NPM),
    //     //     abi.encodeWithSelector(INonfungiblePositionManager(NPM).positions.selector, TEST_NFT),
    //     //     abi.encode(0, 0, 0, 0, 0, 0, 0, 0, liquidityBefore, 0, 0, 0, 0)
    //     // );

    //     // Create Instructions struct with specified values
    //     V3Utils.Instructions memory inst = V3Utils.Instructions(
    //         V3Utils.WhatToDo.CHANGE_RANGE,
    //         address(usdc),
    //         amountRemoveMin0,
    //         amountRemoveMin1,
    //         1000000000000000001,
    //         400000,
    //         _get05DAIToUSDCSwapData(),
    //         0,
    //         0,
    //         "", // swapData1
    //         type(uint128).max,
    //         type(uint128).max,
    //         100, // fee
    //         MIN_TICK_100,
    //         -MIN_TICK_100,
    //         liquidityBefore,
    //         0,
    //         0,
    //         block.timestamp,
    //         TEST_NFT_ACCOUNT,
    //         TEST_NFT_ACCOUNT,
    //         false,
    //         "",
    //         ""
    //     );

    //     // Encode the function call for safeTransferFrom
    //     bytes memory transferData = abi.encodeWithSignature(
    //         "safeTransferFrom(address,address,uint256,bytes)",
    //         TEST_NFT_ACCOUNT,
    //         address(v3utils),
    //         TEST_NFT,
    //         abi.encode(inst)
    //     );

    //     // Expect revert with "Price slippage check"
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     vm.expectRevert("Price slippage check");

    //     // Perform the low-level call to safeTransferFrom
    //     (bool success, bytes memory returnData) = address(NPM).call(transferData);
    //     assert(!success);
    // }

    // function testFuzzTransferDecreaseSlippageError_Ticks(
    //     int24 tickLower,
    //     int24 tickUpper
    // ) external { //@audit => invalid token ID
    //     // Assume conditions for tickLower and tickUpper to avoid conversion issues
    //     vm.assume(tickLower >= type(int24).min && tickLower < type(int24).max);
    //     vm.assume(tickUpper > tickLower && tickUpper <= type(int24).max);

    //     // Add liquidity to the existing (empty) position
    //     _increaseLiquidity();

    //     // Mock the positions call to return the specified liquidity
    //     vm.mockCall(
    //         address(NPM),
    //         abi.encodeWithSelector(INonfungiblePositionManager(NPM).positions.selector, TEST_NFT),
    //         abi.encode(0, 0, 0, 0, 0, 0, 0, 0, 2001002825163355, 0, 0, 0, 0)
    //     );

    //     // Create Instructions struct with specified values
    //     V3Utils.Instructions memory inst = V3Utils.Instructions(
    //         V3Utils.WhatToDo.CHANGE_RANGE,
    //         address(usdc),
    //         1000000000000000001,
    //         400000,
    //         1000000000000000001,
    //         400000,
    //         _get05DAIToUSDCSwapData(),
    //         0,
    //         0,
    //         "", // swapData1
    //         type(uint128).max,
    //         type(uint128).max,
    //         100, // fee
    //         tickLower,
    //         tickUpper,
    //         2001002825163355,
    //         0,
    //         0,
    //         block.timestamp,
    //         TEST_NFT_ACCOUNT,
    //         TEST_NFT_ACCOUNT,
    //         false,
    //         "",
    //         ""
    //     );

    //     // Encode the function call for safeTransferFrom
    //     bytes memory transferData = abi.encodeWithSignature(
    //         "safeTransferFrom(address,address,uint256,bytes)",
    //         TEST_NFT_ACCOUNT,
    //         address(v3utils),
    //         TEST_NFT,
    //         abi.encode(inst)
    //     );

    //     // Expect revert with "Price slippage check"
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     vm.expectRevert("Price slippage check");

    //     // Perform the low-level call to safeTransferFrom
    //     (bool success, bytes memory returnData) = address(NPM).call(transferData);
    //     assert(!success);
    // }

    // function testFuzzSwapAndMint(
    //     int24 lower,
    //     int24 upper,
    //     uint256 amountIn
    // ) external { //@audit => assert failed revert
    //     // Ensure lower and upper are within the valid int24 range
    //     vm.assume(lower >= -887220 && lower <= 887220);
    //     vm.assume(upper >= lower + 1 && upper <= 887220);

    //     // Set a predefined balance of USDC for the TEST_NFT_ACCOUNT
    //     uint256 initialBalanceUSDC = 2000000;
    //     deal(address(usdc), TEST_NFT_ACCOUNT, initialBalanceUSDC);

    //     // Ensure amountIn is within the balance of TEST_NFT_ACCOUNT
    //     amountIn = bound(amountIn, 1, initialBalanceUSDC);

    //     // Create SwapAndMintParams struct with specified values
    //     V3Utils.SwapAndMintParams memory params = V3Utils.SwapAndMintParams(
    //         dai,
    //         usdc,
    //         500,
    //         lower,
    //         upper,
    //         0,
    //         2000000,
    //         TEST_NFT_ACCOUNT,
    //         TEST_NFT_ACCOUNT,
    //         block.timestamp,
    //         usdc,
    //         amountIn,
    //         900000000000000000,
    //         _get1USDCToDAISwapData(),
    //         0,
    //         0,
    //         "",
    //         0,
    //         0,
    //         "",
    //         ""
    //     );

    //     // Approve the v3utils contract to manage the USDC
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     (bool success, bytes memory result) = address(usdc).call(
    //         abi.encodeWithSignature("approve(address,uint256)", address(v3utils), 2000000)
    //     );
    //     assert(success);

    //     // Perform the low-level call to swapAndMint
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     (success, result) = address(v3utils).call(
    //         abi.encodeWithSignature(
    //             "swapAndMint((address,address,uint24,int24,int24,uint256,uint256,address,address,uint256,address,uint256,uint256,bytes,uint256,uint256,bytes,uint256,uint256,bytes,bytes))",
    //             params
    //         )
    //     );
    //     assert(success);

    //     // Decode the returned data
    //     (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = abi.decode(result, (uint256, uint128, uint256, uint256));

    //     // Perform the assertions
    //     uint256 feeBalance = dai.balanceOf(TEST_FEE_ACCOUNT);
    //     assertGt(feeBalance, 0);  // Check if any fee was collected

    //     assertGt(tokenId, 0); // Token ID should be greater than 0
    //     assertGt(liquidity, 0); // Liquidity should be greater than 0
    //     assertGt(amount0, 0); // Amount0 should be greater than 0
    //     assertGt(amount1, 0); // Amount1 should be greater than 0
    // }

    // function testFuzzIncreaseLiquidity(
    //     uint256 amountIn0,
    //     uint256 amountIn1
    // ) external { //@audit => no visible
    //     // Asegurarse de que los valores de entrada estén dentro de un rango razonable
    //     amountIn0 = bound(amountIn0, 1, 1000000000000000000);
    //     amountIn1 = bound(amountIn1, 0, 1000000000000000000);

    //     // Configurar el saldo inicial de DAI para TEST_NFT_ACCOUNT
    //     uint256 initialBalanceDAI = 1000000000000000000;
    //     deal(address(dai), TEST_NFT_ACCOUNT, initialBalanceDAI);

    //     // Crear el struct SwapAndIncreaseLiquidityParams con los valores especificados
    //     V3Utils.SwapAndIncreaseLiquidityParams memory params = V3Utils.SwapAndIncreaseLiquidityParams(
    //         TEST_NFT,
    //         amountIn0,
    //         amountIn1,
    //         TEST_NFT_ACCOUNT,
    //         block.timestamp,
    //         IERC20(address(0)),
    //         0,
    //         0,
    //         "",
    //         0,
    //         0,
    //         "",
    //         0,
    //         0,
    //         ""
    //     );

    //     uint256 balanceBefore = dai.balanceOf(TEST_NFT_ACCOUNT);

    //     // Aprobar el contrato v3utils para manejar DAI
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     (bool success, ) = address(dai).call(
    //         abi.encodeWithSignature("approve(address,uint256)", address(v3utils), 1000000000000000000)
    //     );
    //     assert(success);

    //     // Realizar la llamada de bajo nivel a swapAndIncreaseLiquidity
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     (success, ) = address(v3utils).call(
    //         abi.encodeWithSignature(
    //             "swapAndIncreaseLiquidity((uint256,uint256,uint256,address,uint256,address,uint256,uint256,bytes,uint256,uint256,bytes,uint256,uint256,bytes))",
    //             params
    //         )
    //     );
    //     assert(success);

    //     // Obtener los datos de la posición para validar los resultados
    //     (,,,,,,, uint128 liquidity, uint256 amount0, uint256 amount1) = v3utils.positions(TEST_NFT);

    //     uint256 balanceAfter = dai.balanceOf(TEST_NFT_ACCOUNT);

    //     // Verificaciones
    //     assertEq(balanceBefore - balanceAfter, amountIn0);
    //     assertEq(liquidity, 2001002825163355);
    //     assertEq(amount0, amountIn0); // added amount
    //     assertEq(amount1, amountIn1); // added amount on the other side

    //     uint256 balanceDAI = dai.balanceOf(address(v3utils));
    //     uint256 balanceUSDC = usdc.balanceOf(address(v3utils));

    //     assertEq(balanceDAI, 0);
    //     assertEq(balanceUSDC, 0);
    // }

    // function testFuzzSwapAndMint(
    //     int24 lower,
    //     int24 upper
    // ) external { //@audit => fail memory
    //     // Configurar los límites razonables para los parámetros
    //     lower = int24(bound(uint256(int256(lower)), -887220, 887220));
    //     upper = int24(bound(uint256(int256(upper)), lower + 1, 887220));

    //     // Configurar el saldo inicial de USDC para TEST_NFT_ACCOUNT
    //     uint256 initialBalanceUSDC = 2000000;
    //     vm.deal(address(usdc), TEST_NFT_ACCOUNT, initialBalanceUSDC);

    //     // Crear el struct SwapAndMintParams con los valores especificados
    //     V3Utils.SwapAndMintParams memory params = V3Utils.SwapAndMintParams(
    //         dai,
    //         usdc,
    //         500,
    //         lower,
    //         upper,
    //         0,
    //         initialBalanceUSDC,
    //         TEST_NFT_ACCOUNT,
    //         TEST_NFT_ACCOUNT,
    //         block.timestamp,
    //         usdc,
    //         1000000,
    //         900000000000000000,
    //         _get1USDCToDAISwapData(),
    //         0,
    //         0,
    //         "",
    //         0,
    //         0,
    //         "",
    //         ""
    //     );

    //     // Aprobar el contrato v3utils para manejar USDC
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     (bool success, ) = address(usdc).call(
    //         abi.encodeWithSignature("approve(address,uint256)", address(v3utils), initialBalanceUSDC)
    //     );
    //     assert(success);

    //     // Realizar la llamada de bajo nivel a swapAndMint
    //     vm.prank(TEST_NFT_ACCOUNT);
    //     (success, bytes memory data) = address(v3utils).call(
    //         abi.encodeWithSignature(
    //             "swapAndMint((address,address,uint24,int24,int24,uint256,uint256,address,address,uint256,address,uint256,uint256,bytes,uint256,uint256,bytes,uint256,uint256,bytes,bytes))",
    //             params
    //         )
    //     );
    //     assert(success);

    //     // Decodificar los datos retornados
    //     (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint128, uint256, uint256));

    //     // Verificaciones
    //     uint256 feeBalance = dai.balanceOf(TEST_FEE_ACCOUNT);
    //     assertGt(feeBalance, 0);

    //     assertGt(tokenId, 0);
    //     assertGt(liquidity, 0);
    //     assertGt(amount0, 0);
    //     assertGt(amount1, 0);
    // }

// ============================================
// ==                HELPHER                 ==
// ============================================


    function _increaseLiquidity() internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        V3Utils.SwapAndIncreaseLiquidityParams memory params = V3Utils.SwapAndIncreaseLiquidityParams(
            TEST_NFT,
            1000000000000000000,
            0,
            TEST_NFT_ACCOUNT,
            block.timestamp,
            IERC20(address(0)),
            0, // no swap
            0,
            "",
            0, // no swap
            0,
            "",
            0,
            0,
            ""
        );

        uint256 balanceBefore = dai.balanceOf(TEST_NFT_ACCOUNT);

        vm.startPrank(TEST_NFT_ACCOUNT);
        dai.approve(address(v3utils), 1000000000000000000);
        (liquidity, amount0, amount1) = v3utils.swapAndIncreaseLiquidity(params);
        vm.stopPrank();

        uint256 balanceAfter = dai.balanceOf(TEST_NFT_ACCOUNT);

        // uniswap sometimes adds not full balance (this tests that leftover tokens were returned correctly)
        assertEq(balanceBefore - balanceAfter, 999999999999999633);

        assertEq(liquidity, 2001002825163355);
        assertEq(amount0, 999999999999999633); // added amount
        assertEq(amount1, 0); // only added on one side

        uint256 balanceDAI = dai.balanceOf(address(v3utils));
        uint256 balanceUSDC = usdc.balanceOf(address(v3utils));

        assertEq(balanceDAI, 0);
        assertEq(balanceUSDC, 0);
    }


    function _get05DAIToUSDCSwapData() internal view returns (bytes memory) {
        // https://api.0x.org/swap/v1/quote?sellToken=DAI&buyToken=USDC&sellAmount=500000000000000000&slippagePercentage=0.01&feeRecipient=0x8df57E3D9dDde355dCE1adb19eBCe93419ffa0FB&buyTokenPercentageFee=0.01
        return abi.encode(
            EX0x,
            abi.encode(
                Swapper.ZeroxRouterData(
                    EX0x,
                    hex"415565b00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000006f05b59d3b2000000000000000000000000000000000000000000000000000000000000000777fa00000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000001900000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000006f05b59d3b200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000025368696261537761700000000000000000000000000000000000000000000000000000000000000006f05b59d3b200000000000000000000000000000000000000000000000000000000000000078b18000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000003f7724180aa6b939894b5ca4314783b0b36b329000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000131e0000000000000000000000008df57e3d9ddde355dce1adb19ebce93419ffa0fb0000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000bde5ecabc66356c0b3"
                )
            )
        );
    }

    function _get1USDCToDAISwapData() internal view returns (bytes memory) {
        // https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&sellAmount=1000000&slippagePercentage=0.01&feeRecipient=0x8df57E3D9dDde355dCE1adb19eBCe93419ffa0FB&buyTokenPercentageFee=0.01
        return abi.encode(
            EX0x,
            abi.encode(
                Swapper.ZeroxRouterData(
                    EX0x,
                    hex"415565b0000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000da9d72c692dbf4e00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000000190000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000034000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000025375736869537761700000000000000000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000dccd1a52cca5d60000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000022fa78c39c9e120000000000000000000000008df57e3d9ddde355dce1adb19ebce93419ffa0fb0000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000d5d77f6b6f6356bff0"
                )
            )
        );
    }


}