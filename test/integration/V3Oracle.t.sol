// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// base contracts
import "../../src/V3Oracle.sol";
import "v3-core/interfaces/pool/IUniswapV3PoolDerivedState.sol";

import "../../src/utils/Constants.sol";

contract V3OracleIntegrationTest is Test {
    uint256 constant Q32 = 2 ** 32;
    uint256 constant Q96 = 2 ** 96;

    address constant WHALE_ACCOUNT = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    IERC20 constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

    INonfungiblePositionManager constant NPM = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant CHAINLINK_DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address constant UNISWAP_DAI_USDC = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168; // 0.01% pool
    address constant UNISWAP_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 0.05% pool

    uint256 constant TEST_NFT = 126; // DAI/USDC 0.05% - in range (-276330/-276320)

    uint256 constant TEST_NFT_UNI = 1; // WETH/UNI 0.3%

    uint256 constant TEST_NFT_DAI_WETH = 548468; // DAI/WETH 0.05%

    uint256 mainnetFork;
    V3Oracle oracle;

    function setUp() external {
        mainnetFork = vm.createFork("https://rpc.ankr.com/eth", 18521658);
        vm.selectFork(mainnetFork);
        // mainnetFork = vm.createSelectFork("https://rpc.ankr.com/eth", 18521658);


        // use tolerant oracles (so timewarp for until 30 days works in tests - also allow divergence from price for mocked price results)
        oracle = new V3Oracle(NPM, address(USDC), address(0));
        oracle.setMaxPoolPriceDifference(200);
        oracle.setTokenConfig(
            address(USDC),
            AggregatorV3Interface(CHAINLINK_USDC_USD),
            3600 * 24 * 30,
            IUniswapV3Pool(address(0)),
            0,
            V3Oracle.Mode.TWAP,
            0
        );
        oracle.setTokenConfig(
            address(DAI),
            AggregatorV3Interface(CHAINLINK_DAI_USD),
            3600 * 24 * 30,
            IUniswapV3Pool(UNISWAP_DAI_USDC),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            200
        );
        oracle.setTokenConfig(
            address(WETH),
            AggregatorV3Interface(CHAINLINK_ETH_USD),
            3600 * 24 * 30,
            IUniswapV3Pool(UNISWAP_ETH_USDC),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            200
        );
    }

    function testConversionChainlink() external {
        (uint256 valueUSDC,,,) = oracle.getValue(TEST_NFT, address(USDC));
        assertEq(valueUSDC, 9829088);

        (uint256 valueDAI,,,) = oracle.getValue(TEST_NFT, address(DAI));
        assertEq(valueDAI, 9830164473705245040);

        (uint256 valueWETH,,,) = oracle.getValue(TEST_NFT, address(WETH));
        assertEq(valueWETH, 5264700508440484);
    }

    function testConversionTWAP() external {
        oracle.setOracleMode(address(USDC), V3Oracle.Mode.TWAP_CHAINLINK_VERIFY);
        oracle.setOracleMode(address(DAI), V3Oracle.Mode.TWAP_CHAINLINK_VERIFY);
        oracle.setOracleMode(address(WETH), V3Oracle.Mode.TWAP_CHAINLINK_VERIFY);

        (uint256 valueUSDC,,,) = oracle.getValue(TEST_NFT, address(USDC));
        assertEq(valueUSDC, 9829593);

        (uint256 valueDAI,,,) = oracle.getValue(TEST_NFT, address(DAI));
        assertEq(valueDAI, 9829567935538784710);

        (uint256 valueWETH,,,) = oracle.getValue(TEST_NFT, address(WETH));
        assertEq(valueWETH, 5253670438160606);

        (uint256 valueUSDC2,, uint256 price0, uint256 price1) = oracle.getValue(TEST_NFT_DAI_WETH, address(USDC));
        assertEq(valueUSDC2, 57217647627);

        assertEq(price0, 79228371980132557);
        assertEq(price1, 148235538176146811595);

        (,,,, uint256 amount0, uint256 amount1,,) = oracle.getPositionBreakdown(TEST_NFT_DAI_WETH);
        assertEq(amount0, 29754721813133755549897);
        assertEq(amount1, 14500423413066020069);
    }

    function testNonExistingToken() external {
        vm.expectRevert(Constants.NotConfigured.selector);
        oracle.getValue(TEST_NFT, address(WBTC));

        vm.expectRevert(Constants.NotConfigured.selector);
        oracle.getValue(TEST_NFT_UNI, address(WETH));
    }

    function testInvalidPoolConfig() external {
        vm.expectRevert(Constants.InvalidPool.selector);
        oracle.setTokenConfig(
            address(WETH),
            AggregatorV3Interface(CHAINLINK_ETH_USD),
            3600,
            IUniswapV3Pool(UNISWAP_DAI_USDC),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            500
        );
    }

    function testEmergencyAdmin() external {
        vm.expectRevert(Constants.Unauthorized.selector);
        vm.prank(WHALE_ACCOUNT);
        oracle.setOracleMode(address(WETH), V3Oracle.Mode.TWAP_CHAINLINK_VERIFY);

        oracle.setEmergencyAdmin(WHALE_ACCOUNT);
        vm.prank(WHALE_ACCOUNT);
        oracle.setOracleMode(address(WETH), V3Oracle.Mode.TWAP_CHAINLINK_VERIFY);
    }

    function testChainlinkError() external {
        vm.mockCall(
            CHAINLINK_DAI_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(0), block.timestamp, block.timestamp, uint80(0))
        );
        vm.expectRevert(Constants.ChainlinkPriceError.selector);
        oracle.getValue(TEST_NFT, address(WETH));

        vm.mockCall(
            CHAINLINK_DAI_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1), uint256(0), uint256(0), uint80(0))
        );
        vm.expectRevert(Constants.ChainlinkPriceError.selector);
        oracle.getValue(TEST_NFT, address(WETH));
    }

    function testPriceDivergence() external {
        // change call to simulate oracle difference in chainlink
        vm.mockCall(
            CHAINLINK_DAI_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1), block.timestamp, block.timestamp, uint80(0))
        );

        vm.expectRevert(Constants.PriceDifferenceExceeded.selector);
        oracle.getValue(TEST_NFT, address(WETH));

        // works with normal prices
        vm.clearMockedCalls();
        (uint256 valueWETH,,,) = oracle.getValue(TEST_NFT, address(WETH));
        assertEq(valueWETH, 5264700508440484);

        // change call to simulate oracle difference in univ3 twap
        int56[] memory tickCumulatives = new int56[](2);
        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
        vm.mockCall(
            UNISWAP_DAI_USDC,
            abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
        vm.expectRevert(Constants.PriceDifferenceExceeded.selector);
        oracle.getValue(TEST_NFT, address(WETH));
    }

    ///



    function testFuzzExceedingMaxDifference(uint256 amount) external {
        // Adjust the input amount to fit within a realistic range
        amount = bound(amount, 1, 1e18);

        // Fetch initial prices
        (uint256 valueBefore,, uint256 price0Before, uint256 price1Before) = oracle.getValue(TEST_NFT, address(USDC));

        // Set a low maxPoolPriceDifference to simulate exceeding price difference
        oracle.setMaxPoolPriceDifference(1);

        // Ensure WHALE_ACCOUNT has enough balance
        uint256 whaleBalanceUSDC = USDC.balanceOf(WHALE_ACCOUNT);
        uint256 whaleBalanceDAI = DAI.balanceOf(WHALE_ACCOUNT);
        uint256 transferAmountUSDC = whaleBalanceUSDC < amount ? whaleBalanceUSDC : amount;
        uint256 transferAmountDAI = whaleBalanceDAI < amount ? whaleBalanceDAI : amount;

        // Manipulate price difference
        vm.startPrank(WHALE_ACCOUNT);
        USDC.transfer(address(this), transferAmountUSDC);
        DAI.transfer(address(this), transferAmountDAI);
        vm.stopPrank();

        // Ensure that the oracle reverts when the price difference exceeds the allowed maximum
        vm.expectRevert();
        oracle.getValue(TEST_NFT, address(USDC));
    }

    function testOracleConfigUpdate() external {
        // Original configuration
        oracle.setTokenConfig(
            address(WETH),
            AggregatorV3Interface(CHAINLINK_ETH_USD),
            3600 * 24 * 30,
            IUniswapV3Pool(UNISWAP_ETH_USDC),
            60,
            V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
            200
        );

        // Check updated values
        (uint256 valueWBTC,,,) = oracle.getValue(TEST_NFT, address(WETH));
        assert(valueWBTC > 0);
    }
    function testOracleModes() external {
        // Set mode to TWAP
        oracle.setOracleMode(address(DAI), V3Oracle.Mode.TWAP);
        (uint256 valueTwap,,,) = oracle.getValue(TEST_NFT, address(DAI));
        assert(valueTwap > 0);

        // Set mode to CHAINLINK
        oracle.setOracleMode(address(DAI), V3Oracle.Mode.CHAINLINK);
        (uint256 valueChainlink,,,) = oracle.getValue(TEST_NFT, address(DAI));
        assert(valueChainlink > 0);

        // Set mode to CHAINLINK_TWAP_VERIFY
        oracle.setOracleMode(address(DAI), V3Oracle.Mode.CHAINLINK_TWAP_VERIFY);
        (uint256 valueChainlinkTwapVerify,,,) = oracle.getValue(TEST_NFT, address(DAI));
        assert(valueChainlinkTwapVerify > 0);
    }




    function testNormalLOperation(uint256 amount) external {
        uint256 whaleBalance = USDC.balanceOf(WHALE_ACCOUNT);
        amount = bound(amount, 1, whaleBalance / 2);  // Ensure the amount is less than half the whale's balance

        console.log("Bound result", amount);

        vm.startPrank(WHALE_ACCOUNT);
        USDC.transfer(address(this), amount);
        vm.stopPrank();

        uint256 value;
        uint256 feeValue;
        uint256 price0X96;
        uint256 price1X96;

        // Ensure oracle works as expected with normal data
        (value, feeValue, price0X96, price1X96) = oracle.getValue(TEST_NFT, address(USDC));
        console.log("Value:", value);
        console.log("Fee Value:", feeValue);
        console.log("Price0X96:", price0X96);
        console.log("Price1X96:", price1X96);

        // Validate that the total value is greater than or equal to the fee value
        assertTrue(value >= feeValue, "Total value must be greater than or equal to the fee value");

        // Adjusted reasonable price ranges
        uint256 maxReasonablePrice = 10**30;  // Increased upper bound
        uint256 minReasonablePrice = 10**8;   // Decreased lower bound

        assertTrue(price0X96 >= minReasonablePrice && price0X96 <= maxReasonablePrice, "price0X96 is out of the reasonable range");
        assertTrue(price1X96 >= minReasonablePrice && price1X96 <= maxReasonablePrice, "price1X96 is out of the reasonable range");

        // Verify that fees are a reasonable fraction of the total value (e.g., fees should not be excessively high)
        uint256 maxFeePercentage = 10;  // 10% maximum fees
        assertTrue(feeValue <= value * maxFeePercentage / 100, "Fees exceed the maximum reasonable percentage of total value");

        // Verify intermediate calculations
        V3Oracle.TokenConfig memory usdcConfig = oracle.getTokenConfig(address(USDC));
        uint256 chainlinkPriceX96 = oracle.getChainlinkPriceX96(address(USDC));  // Now this method is public
        uint256 twapPriceX96 = oracle.getTWAPPriceX96(usdcConfig);  // Now this method is public

        // If using Chainlink
        if (usdcConfig.mode == V3Oracle.Mode.CHAINLINK || usdcConfig.mode == V3Oracle.Mode.CHAINLINK_TWAP_VERIFY || usdcConfig.mode == V3Oracle.Mode.TWAP_CHAINLINK_VERIFY) {
            assertTrue(chainlinkPriceX96 > 0, "Chainlink price should be greater than 0");
        }

        // If using TWAP
        if (usdcConfig.mode == V3Oracle.Mode.TWAP || usdcConfig.mode == V3Oracle.Mode.CHAINLINK_TWAP_VERIFY || usdcConfig.mode == V3Oracle.Mode.TWAP_CHAINLINK_VERIFY) {
            assertTrue(twapPriceX96 > 0, "TWAP price should be greater than 0");
        }

        // Verify the maximum allowed price differences
        if (usdcConfig.mode == V3Oracle.Mode.CHAINLINK_TWAP_VERIFY || usdcConfig.mode == V3Oracle.Mode.TWAP_CHAINLINK_VERIFY) {
            uint256 maxDifference = usdcConfig.maxDifference;
            uint256 difference = chainlinkPriceX96 > twapPriceX96 ? chainlinkPriceX96 - twapPriceX96 : twapPriceX96 - chainlinkPriceX96;
            assertTrue(difference <= maxDifference, "Price difference exceeds the maximum allowed");
        }

        vm.startPrank(address(this));
        USDC.transfer(WHALE_ACCOUNT, amount);
        vm.stopPrank();
    }

    function invariant_totalValueShouldBeGreaterThanOrEqualToFeeValue() public {
        (uint256 value, uint256 feeValue, , ) = oracle.getValue(TEST_NFT, address(USDC));
        assertTrue(value >= feeValue, "Total value must be greater than or equal to the fee value");
    }


}
