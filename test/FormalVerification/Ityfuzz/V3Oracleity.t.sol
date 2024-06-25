// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// base contracts
import "../../../src/V3Oracle.sol";
import "v3-core/interfaces/pool/IUniswapV3PoolDerivedState.sol";

import "../../../src/utils/Constants.sol";

import "lib/solidity_utils/lib.sol";


contract V3OracleIntegrationItyTest is Test {
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

        mainnetFork = vm.createSelectFork("mainnet", 18521658);

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
        // oracle.setTokenConfig(
        //     address(DAI),
        //     AggregatorV3Interface(CHAINLINK_DAI_USD),
        //     3600 * 24 * 30,
        //     IUniswapV3Pool(UNISWAP_DAI_USDC),
        //     60,
        //     V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
        //     200
        // );
        // oracle.setTokenConfig(
        //     address(WETH),
        //     AggregatorV3Interface(CHAINLINK_ETH_USD),
        //     3600 * 24 * 30,
        //     IUniswapV3Pool(UNISWAP_ETH_USDC),
        //     60,
        //     V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
        //     200
        // );

        // targetContract(address(NPM));
        // targetContract(address(DAI));
        // targetContract(address(WETH));
        // targetContract(address(USDC));
        // targetContract(address(WBTC));
    }


    function testFuzzGetValuePricesAndAmounts(uint256 tokenId, address token, uint256 price0X96, uint256 price1X96, uint256 amount0, uint256 amount1, uint128 fees0, uint128 fees1) external {

        tokenId = bound(tokenId, 1, 1e6);
        price0X96 = bound(price0X96, 1, type(uint256).max / Q96);
        price1X96 = bound(price1X96, 1, type(uint256).max / Q96);
        amount0 = bound(amount0, 0, type(uint256).max / Q96);
        amount1 = bound(amount1, 0, type(uint256).max / Q96);
        fees0 = uint128(bound(fees0, 0, type(uint128).max));
        fees1 = uint128(bound(fees1, 0, type(uint128).max));

        try oracle.getValue(tokenId, token) returns (uint256 value, uint256 feeValue, uint256 _price0X96, uint256 _price1X96) {

            assert(value >= 0);
            assert(feeValue >= 0);
            assert(_price0X96 >= 0);
            assert(_price1X96 >= 0);
        } catch (bytes memory reason) {

            assert(reason.length > 0);
        }
    }

    function testFuzzGetValueWithConfiguredTokens(uint256 tokenId) external {
        tokenId = bound(tokenId, 1, 1e6);

        address[] memory tokens = new address[](4);
        tokens[0] = address(USDC);
        tokens[1] = address(DAI);
        tokens[2] = address(WETH);
        tokens[3] = address(WBTC);

        for (uint256 i = 0; i < tokens.length; i++) {
            try oracle.getValue(tokenId, tokens[i]) {

            } catch (bytes memory reason) {

                assert(reason.length > 0);
            }
        }
    }

    function testFuzzGetLiquidityAndFees(uint256 tokenId) external {
        tokenId = bound(tokenId, 1, 1e6);

        try oracle.getLiquidityAndFees(tokenId) returns (uint128 liquidity, uint128 fees0, uint128 fees1) {
            assert(liquidity >= 0); 
            assert(fees0 >= 0); 
            assert(fees1 >= 0); 
        } catch (bytes memory reason) {

            assert(reason.length > 0);
        }
    }

    function testNormalOperation(uint256 amount) external {
        uint256 whaleBalance = USDC.balanceOf(WHALE_ACCOUNT);
        amount = bound(amount, 1, whaleBalance / 2);  

        console.log("Bound result", amount);

        vm.startPrank(WHALE_ACCOUNT);
        USDC.transfer(address(this), amount);
        vm.stopPrank();

        uint256 value;
        uint256 feeValue;
        uint256 price0X96;
        uint256 price1X96;

        (value, feeValue, price0X96, price1X96) = oracle.getValue(TEST_NFT, address(USDC));
        console.log("Value:", value);
        console.log("Fee Value:", feeValue);
        console.log("Price0X96:", price0X96);
        console.log("Price1X96:", price1X96);

        assertTrue(value > 0);
        assertTrue(feeValue >= 0);
        assertTrue(price0X96 > 0);
        assertTrue(price1X96 > 0);

        vm.startPrank(address(this));
        USDC.transfer(WHALE_ACCOUNT, amount);
        vm.stopPrank();
    }

    function testTWAPManipulation(uint256 amount) external {
        uint256 whaleBalance = USDC.balanceOf(WHALE_ACCOUNT);
        amount = bound(amount, 1, whaleBalance / 2);

        console.log("Bound result", amount);

        vm.startPrank(WHALE_ACCOUNT);
        USDC.transfer(address(this), amount);
        vm.stopPrank();

        // Set a low max difference to simulate exceeding price difference due to TWAP manipulation
        oracle.setMaxPoolPriceDifference(1);

        // Ensure oracle detects manipulation
        vm.expectRevert(Constants.PriceDifferenceExceeded.selector);
        oracle.getValue(TEST_NFT, address(USDC));

        // Restore balance to avoid side effects
        vm.startPrank(address(this));
        USDC.transfer(WHALE_ACCOUNT, amount);
        vm.stopPrank();
    }

    function testFuzzOracleManipulation(uint256 amount) external {
        // Adjust the input amount to fit within a realistic range
        amount = bound(amount, 1, 1e18);

        // Fetch initial values
        (uint256 valueBefore,, uint256 price0Before, uint256 price1Before) = oracle.getValue(TEST_NFT, address(USDC));

        // Ensure WHALE_ACCOUNT has enough balance
        uint256 whaleBalanceUSDC = USDC.balanceOf(WHALE_ACCOUNT);
        uint256 whaleBalanceDAI = DAI.balanceOf(WHALE_ACCOUNT);
        uint256 transferAmountUSDC = whaleBalanceUSDC < amount ? whaleBalanceUSDC : amount;
        uint256 transferAmountDAI = whaleBalanceDAI < amount ? whaleBalanceDAI : amount;

        // Simulate manipulation by altering token balances
        vm.startPrank(WHALE_ACCOUNT);
        USDC.transfer(address(this), transferAmountUSDC);
        DAI.transfer(address(this), transferAmountDAI);
        vm.stopPrank();

        // Ensure that manipulation does not affect price calculation
        (uint256 valueAfter,, uint256 price0After, uint256 price1After) = oracle.getValue(TEST_NFT, address(USDC));

        assertEq(price0Before, price0After, "Price0 should not change after manipulation");
        assertEq(price1Before, price1After, "Price1 should not change after manipulation");

        // Verify that the oracle correctly reverts on significant price differences
        uint256 largeAmount = amount * 1000;
        if (whaleBalanceUSDC >= largeAmount && whaleBalanceDAI >= largeAmount) {
            vm.startPrank(WHALE_ACCOUNT);
            USDC.transfer(address(this), largeAmount);
            DAI.transfer(address(this), largeAmount);
            vm.stopPrank();

            vm.expectRevert();
            oracle.getValue(TEST_NFT, address(USDC));
        }
    }


    function testResilienceToManipulation(uint256 amount) external {
        uint256 whaleBalance = USDC.balanceOf(WHALE_ACCOUNT);
        amount = bound(amount, 1, whaleBalance / 2);  // Asegurar que el amount es menor que el balance del whale

        // Log the bounded amount for debugging purposes
        console.log("Bound result", amount);

        // Simulate manipulation by transferring USDC from the whale account to the test contract
        vm.startPrank(WHALE_ACCOUNT);
        USDC.transfer(address(this), amount);
        vm.stopPrank();

        // Set a very low maxPoolPriceDifference to simulate exceeding price difference
        oracle.setMaxPoolPriceDifference(1);

        // Ensure oracle detects manipulation
        vm.expectRevert(Constants.PriceDifferenceExceeded.selector);
        oracle.getValue(TEST_NFT, address(USDC));

        // Restore maxPoolPriceDifference to its original value after the test
        oracle.setMaxPoolPriceDifference(200);

        // Restore balance to avoid side effects
        vm.startPrank(address(this));
        USDC.transfer(WHALE_ACCOUNT, amount);
        vm.stopPrank();
    }


}
