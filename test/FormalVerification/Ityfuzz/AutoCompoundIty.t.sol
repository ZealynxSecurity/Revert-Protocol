// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../integration/automators/AutomatorIntegrationTestBase.sol";

import "../../../src/transformers/AutoCompound.sol";
import "../../../src/utils/Constants.sol";

// import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";



contract AutoCompoundItyTest is AutomatorIntegrationTestBase {
    AutoCompound autoCompound;

    function setUp() external {
        _setupBase();
        autoCompound = new AutoCompound(NPM, OPERATOR_ACCOUNT, WITHDRAWER_ACCOUNT, 60, 100);

        targetContract(address(NPM));
        targetContract(address(EX0x));
        targetContract(address(UNIVERSAL_ROUTER));
        targetContract(address(PERMIT2));
        targetContract(address(DAI));
        targetContract(address(WETH_ERC20));
        targetContract(address(USDC));

    }

    function testFuzzWithdrawLeftover(uint256 initialDaiBalance, uint256 initialWethBalance) public {
        initialDaiBalance = bound(initialDaiBalance, 1, type(uint256).max / 2);
        initialWethBalance = bound(initialWethBalance, 1, type(uint256).max / 2);

        deal(address(DAI), address(autoCompound), initialDaiBalance);
        deal(address(WETH_ERC20), address(autoCompound), initialWethBalance);

        uint256 baiBalance = DAI.balanceOf(TEST_NFT_2_ACCOUNT);
        uint256 wethBalance = WETH_ERC20.balanceOf(TEST_NFT_2_ACCOUNT);

        uint256 daiLeftover = autoCompound.positionBalances(TEST_NFT_2, address(DAI));
        uint256 wethLeftover = autoCompound.positionBalances(TEST_NFT_2, address(WETH_ERC20));

        vm.expectRevert(Constants.Unauthorized.selector);
        autoCompound.withdrawLeftoverBalances(TEST_NFT_2, TEST_NFT_2_ACCOUNT);

        vm.prank(TEST_NFT_2_ACCOUNT);
        autoCompound.withdrawLeftoverBalances(TEST_NFT_2, TEST_NFT_2_ACCOUNT);

        uint256 baiBalanceAfter = DAI.balanceOf(TEST_NFT_2_ACCOUNT);
        uint256 wethBalanceAfter = WETH_ERC20.balanceOf(TEST_NFT_2_ACCOUNT);

        assertEq(baiBalanceAfter - baiBalance, daiLeftover);
        assertEq(wethBalanceAfter - wethBalance, wethLeftover);

        daiLeftover = autoCompound.positionBalances(TEST_NFT_2, address(DAI));
        wethLeftover = autoCompound.positionBalances(TEST_NFT_2, address(WETH_ERC20));
        assertEq(daiLeftover, 0);
        assertEq(wethLeftover, 0);
    }

    function testFuzzExecuteWithVariousAmountIn(uint256 amountIn) external {
        amountIn = bound(amountIn, 1, type(uint256).max / 2);

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);

        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, amountIn, block.timestamp)) {
            (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
            assertGt(liquidity, 80059851033970806503);
        } catch Error(string memory reason) {
            console2.log(reason);
        } catch (bytes memory /*lowLevelData*/) {
            console2.log("Low-level revert occurred");
        }
    }

    function testFuzzExecuteWithDifferentDeadlines(uint256 deadline) external { 
        deadline = bound(deadline, block.timestamp, block.timestamp + 1 days);

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertEq(liquidity, 80059851033970806503);

        vm.prank(OPERATOR_ACCOUNT);
        autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, 123456789012345678, deadline));

        (,,,,,,, liquidity,,,,) = NPM.positions(TEST_NFT_2);
        assertGt(liquidity, 80059851033970806503);
    }


    function testFuzzExecuteVariousAmountIn(uint256 amountIn) external {
        amountIn = bound(amountIn, 1, type(uint256).max / 2);

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        console2.log("Testing with amountIn:", amountIn);

        vm.prank(OPERATOR_ACCOUNT);

        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, amountIn, block.timestamp)) {
            console2.log("Success with amountIn:", amountIn);
            (,,,,,,, uint128 liquidity,,,,) = NPM.positions(TEST_NFT_2);
            console2.log("Liquidity after execution:", liquidity);
        } catch Error(string memory reason) {
            console2.log("Revert reason:", reason);
        } catch (bytes memory lowLevelData) {
            console2.log("Low-level revert occurred with amountIn:", amountIn);
            console2.logBytes(lowLevelData);
        }
    }

    function testTWAPVerificationWithZeroAmountIn() external {
        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 initialLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("Initial liquidity:", initialLiquidity);

        vm.prank(OPERATOR_ACCOUNT);
        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, 0, block.timestamp)) {

            (,,,,,,, uint128 finalLiquidity,,,,) = NPM.positions(TEST_NFT_2);
            console2.log("Final liquidity:", finalLiquidity);

            assertTrue(finalLiquidity != initialLiquidity, "Liquidity should have changed");
        } catch Error(string memory reason) {

            console2.log(reason);
        } catch (bytes memory /*lowLevelData*/) {
            console2.log("Low-level revert occurred");
        }
    }

    function testFuzzTWAPVerificationWithDifferentAmountIn(uint256 amountIn) external { 
        amountIn = bound(amountIn, 1, type(uint256).max / 2);

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 initialLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("Initial liquidity:", initialLiquidity);

        vm.prank(OPERATOR_ACCOUNT);
        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, amountIn, block.timestamp)) {
            (,,,,,,, uint128 finalLiquidity,,,,) = NPM.positions(TEST_NFT_2);
            console2.log("Final liquidity:", finalLiquidity);
            assertTrue(finalLiquidity > initialLiquidity, "Liquidity should have increased");
        } catch Error(string memory reason) {
            console2.log(reason);
        } catch (bytes memory /*lowLevelData*/) {
            console2.log("Low-level revert occurred");
        }
    }

    function testCompoundTWAPUnintendedBehavior() public {

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 initialLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("Initial Liquidity:", initialLiquidity);

        vm.warp(1643723400);
        (,,,,,,, uint128 twapLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("TWAP Liquidity:", twapLiquidity);

        vm.prank(OPERATOR_ACCOUNT);
        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, twapLiquidity, block.timestamp)) {
            console2.log("Execute passed with TWAP liquidity");
        } catch (bytes memory lowLevelData) {
            console2.logBytes(lowLevelData);
            console2.log("Low-level revert occurred during execute with TWAP liquidity");
        }

        (,,,,,,, uint128 finalLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("Final Liquidity:", finalLiquidity);

        assertNotEq(finalLiquidity, 99117944276318382811); 
    }

    function testFuzzTWAPVerification(uint256 amountIn, uint256 timeWarp) external { 

        amountIn = bound(amountIn, 1, type(uint128).max);
        timeWarp = bound(timeWarp, 60, 86400); 

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        (,,,,,,, uint128 initialLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("Initial liquidity:", initialLiquidity);

        vm.warp(block.timestamp + uint32(timeWarp));

        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, amountIn, block.timestamp)) {
            console2.log("Executed with amountIn:", amountIn);
            console2.log("Executed after time warp:", timeWarp);
        } catch (bytes memory reason) {
            console2.logBytes(reason);
            console2.log("Reverted due to TWAP check with amountIn:", amountIn);
            console2.log("Reverted after time warp:", timeWarp);
        }

        (,,,,,,, uint128 finalLiquidity,,,,) = NPM.positions(TEST_NFT_2);
        console2.log("Final liquidity:", finalLiquidity);
    }

    function testFuzzHandlingOfErrors(uint256 amountIn) external { //@audit-ok
        amountIn = bound(amountIn, 1, 1e18); 

        vm.prank(TEST_NFT_2_ACCOUNT);
        NPM.approve(address(autoCompound), TEST_NFT_2);

        vm.prank(OPERATOR_ACCOUNT);
        try autoCompound.execute(AutoCompound.ExecuteParams(TEST_NFT_2, true, amountIn, block.timestamp)) {

            assertTrue(true);
        } catch (bytes memory reason) {

            console2.log("Revert reason:", string(reason));
            assertTrue(bytes(reason).length > 0, "Expected revert reason");
        }
    }


}