// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BaseCode} from "./BaseAutomators.t.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import{MockToken} from "../mocks/MockToken.sol";

//AutoRange
import "../../../../src/transformers/AutoRange.sol";
import "v3-periphery/libraries/LiquidityAmounts.sol";

//5

contract AutoRangeKTest is BaseCode {

    
// ============================================
// ==                AutoRange                 ==
// ============================================

    function testSetTWAPSeconds() external {

        bytes memory maxtwap = abi.encodeWithSignature("maxTWAPTickDifference()");
        (bool success_maxt, ) = address(autoRange).call(maxtwap);

        bytes memory setTWAP = abi.encodeWithSignature("setTWAPConfig(uint16,uint32)",maxtwap, 120);
        (bool succes_set, ) = address(autoRange).call(setTWAP);
        assertEq(autoRange.TWAPSeconds(), 120);

        vm.expectRevert(Constants.InvalidConfig.selector);
        bytes memory setTWAPAfter = abi.encodeWithSignature("setTWAPConfig(uint16,uint32)",maxtwap, 30);
        (bool succes_setAfter, ) = address(autoRange).call(setTWAPAfter);
    }


    function testAdjustWithoutConfig() external {
        // Simulate the call from TEST_NFT_ACCOUNT to set approval
        vm.prank(TEST_NFT_ACCOUNT);

        // Approve the autoRange contract to manage the NFT
        bytes memory approvalData = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoRange), true);
        (bool approvalSuccess, ) = address(NPM).call(approvalData);
        assert(approvalSuccess);

        // Encode the function call for execute
        AutoRange.ExecuteParams memory executeParams = AutoRange.ExecuteParams(
            TEST_NFT,
            false,
            0,
            "",
            0,
            0,
            0,
            0,
            block.timestamp,
            MAX_REWARD
        );

        bytes memory executeData = abi.encodeWithSignature(
            "execute((uint256,bool,uint256,string,uint256,uint256,uint256,uint256,uint256,uint256))",
            executeParams
        );

        // Expect revert with NotConfigured
        vm.expectRevert(Constants.NotConfigured.selector);
        
        // Simulate the call from OPERATOR_ACCOUNT to execute
        vm.prank(OPERATOR_ACCOUNT);
        (bool success, bytes memory returnData) = address(autoRange).call(executeData);
        assert(!success);
    }

    function testFuzzAdjustWithoutConfig(
        uint256 tokenId,
        bool param1,
        uint256 param2,
        uint256 param3,
        uint256 param4,
        uint256 param5,
        uint256 timestamp
    ) external {
        // Ensure that tokenId and other parameters are within a reasonable range
        vm.assume(tokenId > 0);
        vm.assume(timestamp <= block.timestamp);

        // Simulate the call from TEST_NFT_ACCOUNT to set approval
        vm.prank(TEST_NFT_ACCOUNT);

        // Approve the autoRange contract to manage the NFT
        bytes memory approvalData = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoRange), true);
        (bool approvalSuccess, ) = address(NPM).call(approvalData);
        assert(approvalSuccess);

        // Prepare Execute Parameters
        AutoRange.ExecuteParams memory executeParams = AutoRange.ExecuteParams(
            tokenId,
            param1,
            param2,
            "",
            param3,
            param4,
            param5,
            0,
            timestamp,
            MAX_REWARD
        );

        bytes memory executeData = abi.encodeWithSignature(
            "execute((uint256,bool,uint256,string,uint256,uint256,uint256,uint256,uint256,uint256))",
            executeParams
        );

        // Expect revert with NotConfigured
        vm.expectRevert(Constants.NotConfigured.selector);
        
        // Simulate the call from OPERATOR_ACCOUNT to execute
        vm.prank(OPERATOR_ACCOUNT);
        (bool success, bytes memory returnData) = address(autoRange).call(executeData);
        assert(!success);
    }


    function testFuzzAdjustNotAdjustable(
        int32 lowerTickDelta,
        int32 upperTickDelta,
        uint64 timestamp
    ) external {
        // Ensure the parameters are within a reasonable range
        vm.assume(lowerTickDelta <= upperTickDelta);
        vm.assume(timestamp <= block.timestamp);

        // Simulate the call from TEST_NFT_2_ACCOUNT to set approval
        vm.prank(TEST_NFT_2_ACCOUNT);

        // Approve the autoRange contract to manage the NFT
        bytes memory approvalData = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoRange), true);
        (bool approvalSuccess, ) = address(NPM).call(approvalData);
        assert(approvalSuccess);

        // Mock the ownerOf function for the nonfungible position manager to return TEST_NFT_2_ACCOUNT
        vm.mockCall(
            address(NPM),
            abi.encodeWithSelector(INonfungiblePositionManager(NPM).ownerOf.selector, TEST_NFT_2_A),
            abi.encode(TEST_NFT_2_ACCOUNT)
        );

        // Create PositionConfig struct
        AutoRange.PositionConfig memory configIn = AutoRange.PositionConfig(
            0,  // lowerTickLimit
            0,  // upperTickLimit
            lowerTickDelta,
            upperTickDelta,
            uint64(Q64 / 100),  // token0SlippageX64
            uint64(Q64 / 100),  // token1SlippageX64
            false,
            MAX_REWARD
        );

        // Encode the function call for configToken
        bytes memory configData = abi.encodeWithSignature(
            "configToken(uint256,address,(int32,int32,int32,int32,uint64,uint64,bool,uint64))",
            TEST_NFT_2_A,
            address(0),
            configIn
        );

        // Perform the low-level call to configToken
        vm.prank(TEST_NFT_2_ACCOUNT);
        (bool success, bytes memory returnData) = address(autoRange).call(configData);
        assert(success);

        // Prepare Execute Parameters
        AutoRange.ExecuteParams memory executeParams = AutoRange.ExecuteParams(
            TEST_NFT_2_A,
            false,
            0,
            "",
            0,
            0,
            0,
            0,
            timestamp,
            MAX_REWARD
        );

        bytes memory executeData = abi.encodeWithSignature(
            "execute((uint256,bool,uint256,string,uint256,uint256,uint256,uint256,uint256,uint64))",
            executeParams
        );

        // Expect revert with NotReady
        vm.expectRevert(Constants.NotReady.selector);
        
        // Simulate the call from OPERATOR_ACCOUNT to execute
        vm.prank(OPERATOR_ACCOUNT);
        (success, returnData) = address(autoRange).call(executeData);
        assert(!success);
    }


    function testFuzzAdjustOutOfRange(
        int32 lowerTickLimit,
        int32 upperTickLimit,
        uint64 timestamp
    ) external {
        // Ensure the parameters are within a reasonable range
        vm.assume(lowerTickLimit < upperTickLimit);
        vm.assume(timestamp <= block.timestamp);

        // Simulate the call from TEST_NFT_2_ACCOUNT to set approval
        vm.prank(TEST_NFT_2_ACCOUNT);

        // Approve the autoRange contract to manage the NFT
        bytes memory approvalData = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoRange), true);
        (bool approvalSuccess, ) = address(NPM).call(approvalData);
        assert(approvalSuccess);

        // Mock the ownerOf function for the nonfungible position manager to return TEST_NFT_2_ACCOUNT
        vm.mockCall(
            address(NPM),
            abi.encodeWithSelector(INonfungiblePositionManager(NPM).ownerOf.selector, TEST_NFT_2),
            abi.encode(TEST_NFT_2_ACCOUNT)
        );

        // Create PositionConfig struct with out of range values
        AutoRange.PositionConfig memory configIn = AutoRange.PositionConfig(
            lowerTickLimit,  // lowerTickLimit
            upperTickLimit,  // upperTickLimit
            -int32(uint32(type(uint24).max)),
            int32(uint32(type(uint24).max)),
            0,
            0,
            false,
            MAX_REWARD
        );

        // Encode the function call for configToken
        bytes memory configData = abi.encodeWithSignature(
            "configToken(uint256,address,(int32,int32,int32,int32,uint64,uint64,bool,uint64))",
            TEST_NFT_2,
            address(0),
            configIn
        );

        // Perform the low-level call to configToken
        vm.prank(TEST_NFT_2_ACCOUNT);
        (bool success, bytes memory returnData) = address(autoRange).call(configData);
        assert(success);

        // Prepare Execute Parameters
        AutoRange.ExecuteParams memory executeParams = AutoRange.ExecuteParams(
            TEST_NFT_2,
            false,
            0,
            "",
            0,
            0,
            0,
            0,
            timestamp,
            MAX_REWARD
        );

        bytes memory executeData = abi.encodeWithSignature(
            "execute((uint256,bool,uint256,string,uint256,uint256,uint256,uint256,uint256,uint64))",
            executeParams
        );

        // Expect revert with "SafeCast: value doesn't fit in 24 bits"
        vm.expectRevert(abi.encodePacked("SafeCast: value doesn't fit in 24 bits"));
        
        // Simulate the call from OPERATOR_ACCOUNT to execute
        vm.prank(OPERATOR_ACCOUNT);
        (success, returnData) = address(autoRange).call(executeData);
        assert(!success);
    }


    function testFuzzAdjustWithTooLargeSwap(
        uint64 timestamp
    ) external {
        // Ensure the parameters are within a reasonable range
        vm.assume(timestamp <= block.timestamp);

        // Simulate the call from TEST_NFT_2_ACCOUNT to set approval
        vm.prank(TEST_NFT_2_ACCOUNT);

        // Approve the autoRange contract to manage the NFT
        bytes memory approvalData = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoRange), true);
        (bool approvalSuccess, ) = address(NPM).call(approvalData);
        assert(approvalSuccess);

        // Mock the ownerOf function for the nonfungible position manager to return TEST_NFT_2_ACCOUNT
        vm.mockCall(
            address(NPM),
            abi.encodeWithSelector(INonfungiblePositionManager(NPM).ownerOf.selector, TEST_NFT_2),
            abi.encode(TEST_NFT_2_ACCOUNT)
        );

        // Create PositionConfig struct
        AutoRange.PositionConfig memory configIn = AutoRange.PositionConfig(
            0,  // lowerTickLimit
            0,  // upperTickLimit
            0,
            60,
            uint64(Q64 / 100),  // token0SlippageX64
            uint64(Q64 / 100),  // token1SlippageX64
            false,
            MAX_REWARD
        );

        // Encode the function call for configToken
        bytes memory configData = abi.encodeWithSignature(
            "configToken(uint256,address,(int32,int32,int32,int32,uint64,uint64,bool,uint64))",
            TEST_NFT_2,
            address(0),
            configIn
        );

        // Perform the low-level call to configToken
        vm.prank(TEST_NFT_2_ACCOUNT);
        (bool success, bytes memory returnData) = address(autoRange).call(configData);
        assert(success);

        // Prepare Execute Parameters with a too large swap amount
        AutoRange.ExecuteParams memory executeParams = AutoRange.ExecuteParams(
            TEST_NFT_2,
            false,
            type(uint256).max,
            _get03WETHToDAISwapData(),
            0,
            0,
            0,
            0,
            timestamp,
            MAX_REWARD
        );

        bytes memory executeData = abi.encodeWithSignature(
            "execute((uint256,bool,uint256,string,uint256,uint256,uint256,uint256,uint256,uint64))",
            executeParams
        );

        // Expect revert with SwapAmountTooLarge
        vm.expectRevert(Constants.SwapAmountTooLarge.selector);
        
        // Simulate the call from OPERATOR_ACCOUNT to execute
        vm.prank(OPERATOR_ACCOUNT);
        (success, returnData) = address(autoRange).call(executeData);
        assert(!success);
    }


    function testFuzzOracleCheck(
        int32 lowerTickLimit,
        int32 upperTickLimit,
        uint64 timestamp
    ) external {
        // Ensure the parameters are within a reasonable range
        vm.assume(lowerTickLimit <= upperTickLimit);
        vm.assume(timestamp <= block.timestamp);

        // Create AutoRange contract with more strict oracle config
        autoRange = new AutoRange(NPM, OPERATOR_ACCOUNT, WITHDRAWER_ACCOUNT, 60 * 30, 3, EX0x, UNIVERSAL_ROUTER);

        // Simulate the call from TEST_NFT_2_ACCOUNT to set approval
        vm.prank(TEST_NFT_2_ACCOUNT);

        // Approve the autoRange contract to manage the NFT
        bytes memory approvalData = abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoRange), true);
        (bool approvalSuccess, ) = address(NPM).call(approvalData);
        assert(approvalSuccess);

        // Mock the ownerOf function for the nonfungible position manager to return TEST_NFT_2_ACCOUNT
        vm.mockCall(
            address(NPM),
            abi.encodeWithSelector(INonfungiblePositionManager(NPM).ownerOf.selector, TEST_NFT_2),
            abi.encode(TEST_NFT_2_ACCOUNT)
        );

        // Create PositionConfig struct with specified values
        AutoRange.PositionConfig memory configIn = AutoRange.PositionConfig(
            lowerTickLimit,
            upperTickLimit,
            0,
            60,
            uint64(Q64 / 100),  // token0SlippageX64
            uint64(Q64 / 100),  // token1SlippageX64
            false,
            MAX_REWARD
        );

        // Encode the function call for configToken
        bytes memory configData = abi.encodeWithSignature(
            "configToken(uint256,address,(int32,int32,int32,int32,uint64,uint64,bool,uint64))",
            TEST_NFT_2,
            address(0),
            configIn
        );

        // Perform the low-level call to configToken
        vm.prank(TEST_NFT_2_ACCOUNT);
        (bool success, bytes memory returnData) = address(autoRange).call(configData);
        assert(success);

        // Prepare Execute Parameters
        AutoRange.ExecuteParams memory executeParams = AutoRange.ExecuteParams(
            TEST_NFT_2,
            false,
            1000000,
            "",
            0,
            0,
            0,
            0,
            timestamp,
            0
        );

        bytes memory executeData = abi.encodeWithSignature(
            "execute((uint256,bool,uint256,string,uint256,uint256,uint256,uint256,uint256,uint64))",
            executeParams
        );

        // Expect revert with TWAPCheckFailed
        vm.expectRevert(Constants.TWAPCheckFailed.selector);
        
        // Simulate the call from OPERATOR_ACCOUNT to execute
        vm.prank(OPERATOR_ACCOUNT);
        (success, returnData) = address(autoRange).call(executeData);
        assert(!success);
    }

    function _get03WETHToDAISwapData() internal view returns (bytes memory) {
        // https://api.0x.org/swap/v1/quote?sellToken=WETH&buyToken=DAI&sellAmount=300000000000000000&slippagePercentage=0.25
        return abi.encode(
            EX0x,
            abi.encode(
                Swapper.ZeroxRouterData(
                    EX0x,
                    hex"6af479b200000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000429d069189e00000000000000000000000000000000000000000000000000130ac08c36b9dfe37f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f46b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000ce62b248cc6402739e"
                )
            )
        );
    }


}