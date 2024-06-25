// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// base contracts
import "../../../src/InterestRateModel.sol";

contract InterestRateModelFV is Test {
    uint256 constant Q32 = 2 ** 32;
    uint256 constant Q64 = 2 ** 64;

    uint256 constant YEAR_SECS = 31557600; // taking into account leap years

    uint256 mainnetFork;
    InterestRateModel interestRateModel;

    function setUp() external {
        // 5% base rate - after 80% - 109% (like in compound v2 deployed)
        interestRateModel = new InterestRateModel(0, Q64 * 5 / 100, Q64 * 109 / 100, Q64 * 80 / 100);
    }


    function testFuzzUtilizationRates(uint256 cash, uint256 debt) external {
        // Assume cash and debt are within a safe range to prevent overflow
        vm.assume(cash <= type(uint256).max / Q64);
        vm.assume(debt <= type(uint256).max / Q64);

        uint256 utilizationRateX64 = interestRateModel.getUtilizationRateX64(cash, debt);

        // Check that utilization rate is between 0 and Q64
        if (debt == 0) {
            assertEq(utilizationRateX64, 0);
        } else {
            assertLe(utilizationRateX64, Q64);
            assertGe(utilizationRateX64, 0);
        }
    }

    function testFuzzInterestRates(uint256 cash, uint256 debt) external {
        // Assume cash and debt are within a safe range to prevent overflow
        vm.assume(cash <= type(uint256).max / Q64);
        vm.assume(debt <= type(uint256).max / Q64);

        (uint256 borrowRateX64, uint256 lendRateX64) = interestRateModel.getRatesPerSecondX64(cash, debt);

        // Check that rates are non-negative
        assertGe(borrowRateX64, 0);
        assertGe(lendRateX64, 0);

        // If utilization rate is zero, both rates should be zero
        if (debt == 0) {
            assertEq(borrowRateX64, 0);
            assertEq(lendRateX64, 0);
        }

        // Check that the borrow rate is always greater than or equal to the supply rate
        assertGe(borrowRateX64, lendRateX64);
    }


    /////////////////////////////
    //  getUtilizationRateX64  //
    /////////////////////////////

    function testFuzzZeroCashAndDebt(uint256 cash, uint256 debt) external {
        // Ensure cash and debt are zero
        cash = 0;
        debt = 0;
        assertEq(interestRateModel.getUtilizationRateX64(cash, debt), 0);
    }

    function testFuzzMonotonicity(uint256 cash, uint256 debt1, uint256 debt2) external {
        // Ensure cash is within a safe range and debt1 is less than debt2
        vm.assume(cash > 0 && cash <= type(uint256).max / Q64);
        vm.assume(debt1 < debt2 && debt2 <= type(uint256).max / Q64);
        
        uint256 utilizationRate1 = interestRateModel.getUtilizationRateX64(cash, debt1);
        uint256 utilizationRate2 = interestRateModel.getUtilizationRateX64(cash, debt2);
        assertLe(utilizationRate1, utilizationRate2); // Utilization rate should increase with debt
    }

    function testFuzzProportionality(uint256 cash, uint256 debt) external {
        // Ensure cash and debt are non-zero and within a safe range to prevent overflow when multiplied by Q64 and doubled
        uint256 maxSafeValue = type(uint256).max / Q64;
        vm.assume(cash > 0 && cash <= maxSafeValue / 2);
        vm.assume(debt > 0 && debt <= maxSafeValue / 2);

        uint256 cash2 = cash * 2;
        uint256 debt2 = debt * 2;

        uint256 utilizationRate1 = interestRateModel.getUtilizationRateX64(cash, debt);
        uint256 utilizationRate2 = interestRateModel.getUtilizationRateX64(cash2, debt2);
        assertEq(utilizationRate1, utilizationRate2); // Utilization rate should remain the same if both cash and debt are doubled
    }


    /////////////////////////////
    //  getRatesPerSecondX64  //
    /////////////////////////////

    function testFuzzGetRatesPerSecondX64(uint256 cash, uint256 debt) external {
        // Ensure cash and debt are within a safe range to prevent overflow when multiplied by Q64
        uint256 maxSafeValue = type(uint256).max / Q64;
        vm.assume(cash <= maxSafeValue);
        vm.assume(debt <= maxSafeValue);

        (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(cash, debt);

        uint256 utilizationRateX64 = interestRateModel.getUtilizationRateX64(cash, debt);

        // Invariant: Borrow rate should be greater than or equal to base rate
        assertGe(borrowRateX64, interestRateModel.baseRatePerSecondX64());

        // Invariant: Supply rate should be less than or equal to borrow rate
        assertLe(supplyRateX64, borrowRateX64);

        // Invariant: Utilization rate should be between 0 and Q64
        assertLe(utilizationRateX64, Q64);
        assertGe(utilizationRateX64, 0);

        // Invariant: Borrow rate should be non-negative
        assertGe(borrowRateX64, 0);

        // Invariant: Supply rate should be non-negative
        assertGe(supplyRateX64, 0);

        // Specific case when debt is zero: both rates should be zero
        if (debt == 0) {
            assertEq(borrowRateX64, 0);
            assertEq(supplyRateX64, 0);
        }

        // Specific case when cash and debt are zero: both rates should be zero
        if (cash == 0 && debt == 0) {
            assertEq(borrowRateX64, 0);
            assertEq(supplyRateX64, 0);
        }

        // Specific case when utilization is at kink point
        if (utilizationRateX64 == interestRateModel.kinkX64()) {
            uint256 expectedBorrowRateX64 = (utilizationRateX64 * interestRateModel.multiplierPerSecondX64() / Q64) + interestRateModel.baseRatePerSecondX64();
            assertEq(borrowRateX64, expectedBorrowRateX64);
        }

        // Specific case when utilization is above kink point
        if (utilizationRateX64 > interestRateModel.kinkX64()) {
            uint256 normalRateX64 = (uint256(interestRateModel.kinkX64()) * interestRateModel.multiplierPerSecondX64() / Q64) + interestRateModel.baseRatePerSecondX64();
            uint256 excessUtilX64 = utilizationRateX64 - interestRateModel.kinkX64();
            uint256 expectedBorrowRateX64 = (excessUtilX64 * interestRateModel.jumpMultiplierPerSecondX64() / Q64) + normalRateX64;
            assertEq(borrowRateX64, expectedBorrowRateX64);
        }
    }

    function testFuzzBasicInvariants(uint256 cash, uint256 debt) external {
        // Ensure cash and debt are within a safe range to prevent overflow when multiplied by Q64
        uint256 maxSafeValue = type(uint256).max / Q64;
        vm.assume(cash <= maxSafeValue);
        vm.assume(debt <= maxSafeValue);

        (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(cash, debt);

        uint256 utilizationRateX64 = interestRateModel.getUtilizationRateX64(cash, debt);

        // Invariant: Borrow rate should be greater than or equal to base rate
        assertGe(borrowRateX64, interestRateModel.baseRatePerSecondX64());

        // Invariant: Supply rate should be less than or equal to borrow rate
        assertLe(supplyRateX64, borrowRateX64);

        // Invariant: Utilization rate should be between 0 and Q64
        assertLe(utilizationRateX64, Q64);
        assertGe(utilizationRateX64, 0);

        // Invariant: Borrow rate should be non-negative
        assertGe(borrowRateX64, 0);

        // Invariant: Supply rate should be non-negative
        assertGe(supplyRateX64, 0);
    }

    function testFuzzZeroDebt(uint256 cash) external {
        uint256 maxSafeValue = type(uint256).max / Q64;
        vm.assume(cash <= maxSafeValue);

        (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(cash, 0);

        // Specific case when debt is zero: both rates should be zero
        assertEq(borrowRateX64, 0);
        assertEq(supplyRateX64, 0);
    }

    function testFuzzZeroCashAndDebt() external {
        (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(0, 0);

        // Specific case when cash and debt are zero: both rates should be zero
        assertEq(borrowRateX64, 0);
        assertEq(supplyRateX64, 0);
    }

    function testFuzzUtilizationAtKink(uint256 cash) external {
        uint256 maxSafeValue = type(uint256).max / Q64;
        vm.assume(cash > 0 && cash <= maxSafeValue);

        uint256 kinkX64 = interestRateModel.kinkX64();

        // Calculate the debt required to be just below or exactly at the kink utilization rate
        uint256 requiredDebt = (cash * kinkX64) / (Q64 - kinkX64);
        vm.assume(requiredDebt <= maxSafeValue && requiredDebt > 0);  // Ensure the required debt is within a safe range and greater than zero

        // Ensure the utilization rate is less than or equal to kinkX64
        uint256 utilizationRateX64 = interestRateModel.getUtilizationRateX64(cash, requiredDebt);
        vm.assume(utilizationRateX64 <= kinkX64);

        // Calculate the rates
        (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(cash, requiredDebt);

        // Specific case when utilization is at or below kink point
        uint256 multiplierPerSecondX64 = interestRateModel.multiplierPerSecondX64();
        uint256 baseRatePerSecondX64 = interestRateModel.baseRatePerSecondX64();
        uint256 expectedBorrowRateX64 = ((utilizationRateX64 * multiplierPerSecondX64) / Q64) + baseRatePerSecondX64;
        uint256 expectedSupplyRateX64 = (utilizationRateX64 * borrowRateX64) / Q64;

        // Add console logs to debug the values
        console.log("cash:", cash);
        console.log("requiredDebt:", requiredDebt);
        console.log("kinkX64:", kinkX64);
        console.log("utilizationRateX64:", utilizationRateX64);
        console.log("multiplierPerSecondX64:", multiplierPerSecondX64);
        console.log("baseRatePerSecondX64:", baseRatePerSecondX64);
        console.log("expectedBorrowRateX64:", expectedBorrowRateX64);
        console.log("actualBorrowRateX64:", borrowRateX64);
        console.log("expectedSupplyRateX64:", expectedSupplyRateX64);
        console.log("actualSupplyRateX64:", supplyRateX64);

        // Assert the rates
        assertEq(borrowRateX64, expectedBorrowRateX64);
        assertEq(supplyRateX64, expectedSupplyRateX64);
    }

    function testFuzzUtilizationAboveKink(uint256 cash, uint256 debt) external {
        uint256 maxSafeValue = type(uint256).max / Q64;
        vm.assume(cash > 0 && cash <= maxSafeValue);
        vm.assume(debt > 0 && debt <= maxSafeValue);

        uint256 kinkX64 = interestRateModel.kinkX64();

        // Ensure debt is high enough to put utilization above kink
        vm.assume(debt > (cash * kinkX64) / (Q64 - kinkX64));

        // Calculate utilization rate directly and check it
        uint256 utilizationRateX64 = interestRateModel.getUtilizationRateX64(cash, debt);
        vm.assume(utilizationRateX64 > kinkX64);

        (uint256 borrowRateX64, uint256 supplyRateX64) = interestRateModel.getRatesPerSecondX64(cash, debt);

        // Specific case when utilization is above kink point
        uint256 multiplierPerSecondX64 = interestRateModel.multiplierPerSecondX64();
        uint256 baseRatePerSecondX64 = interestRateModel.baseRatePerSecondX64();
        uint256 normalRateX64 = ((kinkX64 * multiplierPerSecondX64) / Q64) + baseRatePerSecondX64;
        uint256 excessUtilX64 = utilizationRateX64 - kinkX64;
        uint256 expectedBorrowRateX64 = ((excessUtilX64 * interestRateModel.jumpMultiplierPerSecondX64()) / Q64) + normalRateX64;
        uint256 expectedSupplyRateX64 = (utilizationRateX64 * expectedBorrowRateX64) / Q64;

        // Add console logs to debug the values
        console.log("cash:", cash);
        console.log("debt:", debt);
        console.log("kinkX64:", kinkX64);
        console.log("utilizationRateX64:", utilizationRateX64);
        console.log("multiplierPerSecondX64:", multiplierPerSecondX64);
        console.log("baseRatePerSecondX64:", baseRatePerSecondX64);
        console.log("normalRateX64:", normalRateX64);
        console.log("excessUtilX64:", excessUtilX64);
        console.log("expectedBorrowRateX64:", expectedBorrowRateX64);
        console.log("actualBorrowRateX64:", borrowRateX64);
        console.log("expectedSupplyRateX64:", expectedSupplyRateX64);
        console.log("actualSupplyRateX64:", supplyRateX64);

        assertEq(borrowRateX64, expectedBorrowRateX64);
        assertEq(supplyRateX64, expectedSupplyRateX64);
    }


    /////////////////////////////
    //  setValues              //
    /////////////////////////////
    
    function testFuzzSetValuesOnlyOwner(
        address nonOwner,
        uint256 baseRatePerYearX64,
        uint256 multiplierPerYearX64,
        uint256 jumpMultiplierPerYearX64,
        uint256 _kinkX64
    ) external {
        vm.assume(nonOwner != address(this));
        vm.prank(nonOwner); // Simulate a call from a non-owner address

        vm.expectRevert("Ownable: caller is not the owner");
        interestRateModel.setValues(baseRatePerYearX64, multiplierPerYearX64, jumpMultiplierPerYearX64, _kinkX64);
    }

    function testFuzzxSetValues(
        uint256 baseRatePerYearX64,
        uint256 multiplierPerYearX64,
        uint256 jumpMultiplierPerYearX64,
        uint256 _kinkX64
    ) external {
        uint256 MAX_BASE_RATE_X64 = interestRateModel.MAX_BASE_RATE_X64();
        uint256 MAX_MULTIPLIER_X64 = interestRateModel.MAX_MULTIPLIER_X64();

        // Ensure the input values fit within 64 bits
        vm.assume(baseRatePerYearX64 <= type(uint64).max);
        vm.assume(multiplierPerYearX64 <= type(uint64).max);
        vm.assume(jumpMultiplierPerYearX64 <= type(uint64).max);
        vm.assume(_kinkX64 <= type(uint64).max);

        // Valid inputs
        vm.assume(baseRatePerYearX64 <= MAX_BASE_RATE_X64);
        vm.assume(multiplierPerYearX64 <= MAX_MULTIPLIER_X64);
        vm.assume(jumpMultiplierPerYearX64 <= MAX_MULTIPLIER_X64);

        // Set values
        interestRateModel.setValues(baseRatePerYearX64, multiplierPerYearX64, jumpMultiplierPerYearX64, _kinkX64);

        // Expected per second values
        uint64 expectedBaseRatePerSecondX64 = uint64(baseRatePerYearX64 / YEAR_SECS);
        uint64 expectedMultiplierPerSecondX64 = uint64(multiplierPerYearX64 / YEAR_SECS);
        uint64 expectedJumpMultiplierPerSecondX64 = uint64(jumpMultiplierPerYearX64 / YEAR_SECS);
        uint64 expectedKinkX64 = uint64(_kinkX64);

        // Check the values
        assertEq(interestRateModel.baseRatePerSecondX64(), expectedBaseRatePerSecondX64);
        assertEq(interestRateModel.multiplierPerSecondX64(), expectedMultiplierPerSecondX64);
        assertEq(interestRateModel.jumpMultiplierPerSecondX64(), expectedJumpMultiplierPerSecondX64);
        assertEq(interestRateModel.kinkX64(), expectedKinkX64);
    }

    function testFuzzSetValuesInvalidConfig(
        uint256 baseRatePerYearX64,
        uint256 multiplierPerYearX64,
        uint256 jumpMultiplierPerYearX64,
        uint256 _kinkX64
    ) external {
        uint256 MAX_BASE_RATE_X64 = interestRateModel.MAX_BASE_RATE_X64();
        uint256 MAX_MULTIPLIER_X64 = interestRateModel.MAX_MULTIPLIER_X64();

        // Constrain the input values to fit within the 64-bit range
        baseRatePerYearX64 = bound(baseRatePerYearX64, 0, type(uint64).max);
        multiplierPerYearX64 = bound(multiplierPerYearX64, 0, type(uint64).max);
        jumpMultiplierPerYearX64 = bound(jumpMultiplierPerYearX64, 0, type(uint64).max);
        _kinkX64 = bound(_kinkX64, 0, type(uint64).max);

        // Invalid inputs: any input that exceeds the max limit
        bool invalidInput = baseRatePerYearX64 > MAX_BASE_RATE_X64
            || multiplierPerYearX64 > MAX_MULTIPLIER_X64
            || jumpMultiplierPerYearX64 > MAX_MULTIPLIER_X64;

        vm.assume(invalidInput);

        // Expect a revert with the correct error signature
        vm.expectRevert(bytes4(keccak256("InvalidConfig()")));
        interestRateModel.setValues(baseRatePerYearX64, multiplierPerYearX64, jumpMultiplierPerYearX64, _kinkX64);
    }

    function testFuzzSetValuesZeroRates(uint256 _kinkX64) external {
        uint256 baseRatePerYearX64 = 0;
        uint256 multiplierPerYearX64 = 0;
        uint256 jumpMultiplierPerYearX64 = 0;

        // Constrain the input value to fit within the 64-bit range
        _kinkX64 = bound(_kinkX64, 0, type(uint64).max);

        // Set values with zero rates
        interestRateModel.setValues(baseRatePerYearX64, multiplierPerYearX64, jumpMultiplierPerYearX64, _kinkX64);

        // Expected per second values
        uint64 expectedBaseRatePerSecondX64 = uint64(baseRatePerYearX64 / YEAR_SECS);
        uint64 expectedMultiplierPerSecondX64 = uint64(multiplierPerYearX64 / YEAR_SECS);
        uint64 expectedJumpMultiplierPerSecondX64 = uint64(jumpMultiplierPerYearX64 / YEAR_SECS);
        uint64 expectedKinkX64 = uint64(_kinkX64);

        // Check the values
        assertEq(interestRateModel.baseRatePerSecondX64(), expectedBaseRatePerSecondX64);
        assertEq(interestRateModel.multiplierPerSecondX64(), expectedMultiplierPerSecondX64);
        assertEq(interestRateModel.jumpMultiplierPerSecondX64(), expectedJumpMultiplierPerSecondX64);
        assertEq(interestRateModel.kinkX64(), expectedKinkX64);
    }


}
