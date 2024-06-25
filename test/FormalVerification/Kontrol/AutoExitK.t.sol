// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BaseCode} from "./BaseAutomators.t.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import{MockToken} from "../mocks/MockToken.sol";

//AutoExit
import "../../../../src/automators/AutoExit.sol";

//5

contract AutoExitKTest is BaseCode {

// ============================================
// ==                AutoExit                 ==
// ============================================


    function testFuzzDirectSendNFT(address from) external {
        vm.assume(from != address(0));
        vm.prank(from);
        vm.expectRevert(abi.encodePacked("ERC721: transfer to non ERC721Receiver implementer"));
        (bool success, ) = address(NPM).call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                from,
                address(autoExit),
                TEST_NFT
            )
        );
        assert(!success);
    }

    uint32 public constant MIN_TWAP_SECONDS = 60; // 1 minute

    function testFuzzSetTWAPSeconds(uint32 newTWAPSeconds) external { 
        uint16 maxTWAPTickDifference = autoExit.maxTWAPTickDifference();

        // Ensure the new TWAPSeconds is in a range that could cause an invalid configuration
        uint32 minValidTWAPSeconds = MIN_TWAP_SECONDS + 1;
        
        // Use assume to ensure newTWAPSeconds is less than MIN_TWAP_SECONDS for invalid configuration
        vm.assume(newTWAPSeconds < MIN_TWAP_SECONDS);

        // Set a valid configuration first
        autoExit.setTWAPConfig(maxTWAPTickDifference, minValidTWAPSeconds);

        // Verify the TWAP seconds
        uint32 twapSeconds = autoExit.TWAPSeconds();
        assertEq(twapSeconds, minValidTWAPSeconds);

        // Expect revert for invalid configuration
        vm.expectRevert();
        autoExit.setTWAPConfig(maxTWAPTickDifference, newTWAPSeconds); // Example of an invalid value
    }


    uint32 public constant MAX_TWAP_TICK_DIFFERENCE = 200; // 2%


    function testFuzzSetMaxTWAPTickDifference(uint16 newMaxTWAPTickDifference) external { 
        uint32 twapSeconds = autoExit.TWAPSeconds();

        // Ensure the new maxTWAPTickDifference is in a range that could cause an invalid configuration
        uint16 maxValidTWAPTickDifference = uint16(MAX_TWAP_TICK_DIFFERENCE - 1);
        
        // Use assume to ensure newMaxTWAPTickDifference is greater than MAX_TWAP_TICK_DIFFERENCE for invalid configuration
        vm.assume(newMaxTWAPTickDifference > MAX_TWAP_TICK_DIFFERENCE);

        // Set a valid configuration first
        autoExit.setTWAPConfig(maxValidTWAPTickDifference, twapSeconds);

        // Verify the maxTWAPTickDifference
        uint16 currentMaxTWAPTickDifference = autoExit.maxTWAPTickDifference();
        assertEq(currentMaxTWAPTickDifference, maxValidTWAPTickDifference);

        // Expect revert for invalid configuration
        vm.expectRevert();
        autoExit.setTWAPConfig(newMaxTWAPTickDifference, twapSeconds); // Example of an invalid value
    }


    function testFuzzSetOperator(address operator, bool status) external { //ok
        // Ensure the operator is not the zero address
        vm.assume(operator != address(0));

        // Set operator status
        autoExit.setOperator(operator, status);

        // Verify the operator status
        bool currentStatus = autoExit.operators(operator);
        assertEq(currentStatus, status);
    }



    function testFuzzRunWithoutConfig(uint256 tokenId) external { 
        // Asegurar que tokenId esté dentro de un rango válido
        vm.assume(tokenId > 0 && tokenId < type(uint256).max);

        // Prank para configurar la aprobación
        vm.prank(TEST_NFT_ACCOUNT);
        (bool approvalSuccess, ) = address(NPM).call(
            abi.encodeWithSignature("setApprovalForAll(address,bool)", address(autoExit), true)
        );
        assert(approvalSuccess);

        // Prank para ejecutar sin configuración
        vm.expectRevert(Constants.NotConfigured.selector);
        vm.prank(OPERATOR_ACCOUNT);
        (bool executeSuccess, ) = address(autoExit).call(
            abi.encodeWithSignature(
                "execute((uint256,string,uint256,uint256,uint256,uint256))",
                AutoExit.ExecuteParams(tokenId, "", 0, 0, block.timestamp, MAX_REWARD)
            )
        );
        // No assert necesario aquí ya que se espera un revert
    }

    function _setConfig(
            uint256 tokenId,
            bool isActive,
            bool token0Swap,
            bool token1Swap,
            uint64 token0SlippageX64,
            uint64 token1SlippageX64,
            int24 token0TriggerTick,
            int24 token1TriggerTick,
            bool onlyFees
        ) internal {
            AutoExit.PositionConfig memory config = AutoExit.PositionConfig(
                isActive,
                token0Swap,
                token1Swap,
                token0TriggerTick,
                token1TriggerTick,
                token0SlippageX64,
                token1SlippageX64,
                onlyFees,
                onlyFees ? MAX_FEE_REWARD : MAX_REWARD
            );

            vm.prank(TEST_NFT_ACCOUNT);
            autoExit.configToken(tokenId, config);
    }


}