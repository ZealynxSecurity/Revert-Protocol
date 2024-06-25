// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// base contracts
import "../../../src/V3Oracle.sol";
import "../../../src/V3Vault.sol";
import "../../../src/InterestRateModel.sol";

// transformers
import "../../../src/transformers/LeverageTransformer.sol";
import "../../../src/transformers/V3Utils.sol";
import "../../../src/transformers/AutoRange.sol";
import "../../../src/transformers/AutoCompound.sol";

import "../../../src/utils/FlashloanLiquidator.sol";

import "../../../src/utils/Constants.sol";

contract V3VaultIntegrationItyTest is Test {
    uint256 constant Q32 = 2 ** 32;
    uint256 constant Q64 = 2 ** 64;
    uint256 constant Q96 = 2 ** 96;

    uint256 constant YEAR_SECS = 31557600; // taking into account leap years

    address constant WHALE_ACCOUNT = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    INonfungiblePositionManager constant NPM = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address EX0x = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // 0x exchange proxy
    address UNIVERSAL_ROUTER = 0xEf1c6E67703c7BD7107eed8303Fbe6EC2554BF6B;
    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address constant CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address constant CHAINLINK_DAI_USD = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address constant UNISWAP_DAI_USDC = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168; // 0.01% pool
    address constant UNISWAP_ETH_USDC = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 0.05% pool
    address constant UNISWAP_DAI_USDC_005 = 0x6c6Bc977E13Df9b0de53b251522280BB72383700; // 0.05% pool

    address constant TEST_NFT_ACCOUNT = 0x3b8ccaa89FcD432f1334D35b10fF8547001Ce3e5;
    uint256 constant TEST_NFT = 126; // DAI/USDC 0.05% - in range (-276330/-276320)

    address constant TEST_NFT_ACCOUNT_2 = 0x454CE089a879F7A0d0416eddC770a47A1F47Be99;
    uint256 constant TEST_NFT_2 = 1047; // DAI/USDC 0.05% - in range (-276330/-276320)

    uint256 constant TEST_NFT_UNI = 1; // WETH/UNI 0.3%

    uint256 constant TEST_NFT_DAI_WETH = 548468; // DAI/WETH 0.05%
    address constant TEST_NFT_DAI_WETH_ACCOUNT = 0x312dEeeF09E8a8BBC4a6ce2b3Fcb395813BE09Df;

    uint256 mainnetFork;

    V3Vault vault;

    InterestRateModel interestRateModel;
    V3Oracle oracle;

    function setUp() external {

        mainnetFork = vm.createSelectFork("mainnet", 18521658);


        // vm.selectFork(mainnetFork);

        // 0% base rate - 5% multiplier - after 80% - 109% jump multiplier (like in compound v2 deployed)  (-> max rate 25.8% per year)
        interestRateModel = new InterestRateModel(0, Q64 * 5 / 100, Q64 * 109 / 100, Q64 * 80 / 100);

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
        //     50000
        // );
        // oracle.setTokenConfig(
        //     address(WETH),
        //     AggregatorV3Interface(CHAINLINK_ETH_USD),
        //     3600 * 24 * 30,
        //     IUniswapV3Pool(UNISWAP_ETH_USDC),
        //     60,
        //     V3Oracle.Mode.CHAINLINK_TWAP_VERIFY,
        //     50000
        // );

        vault = new V3Vault("Revert Lend USDC", "rlUSDC", address(USDC), NPM, interestRateModel, oracle, IPermit2(PERMIT2));
        vault.setTokenConfig(address(USDC), uint32(Q32 * 9 / 10), type(uint32).max); // 90% collateral factor / max 100% collateral value
        vault.setTokenConfig(address(DAI), uint32(Q32 * 9 / 10), type(uint32).max); // 90% collateral factor / max 100% collateral value
        vault.setTokenConfig(address(WETH), uint32(Q32 * 9 / 10), type(uint32).max); // 90% collateral factor / max 100% collateral value

        // limits 15 USDC each
        vault.setLimits(0, 15000000, 15000000, 12000000, 12000000);

        // without reserve for now
        vault.setReserveFactor(0);

        // targetContract(address(NPM));
        // targetContract(address(EX0x));
        // targetContract(address(UNIVERSAL_ROUTER));
        // targetContract(address(PERMIT2));
        // targetContract(address(DAI));
        // targetContract(address(WETH));
        // targetContract(address(USDC));
    }


    function testDepositLimits(uint256 amount) external {
        uint256 balance = USDC.balanceOf(WHALE_ACCOUNT);
        amount = bound(amount, 1, balance * 10);

        vm.prank(WHALE_ACCOUNT);
        USDC.approve(address(vault), amount);

        uint256 lendLimit = vault.globalLendLimit();
        uint256 dailyDepositLimit = vault.dailyLendIncreaseLimitMin();

        if (amount > lendLimit) {
            vm.expectRevert(Constants.GlobalLendLimit.selector);
        } else if (amount > dailyDepositLimit) {
            vm.expectRevert(Constants.DailyLendIncreaseLimit.selector);
        } else if (amount > balance) {
            vm.expectRevert("ERC20: transfer amount exceeds balance");
        }

        vm.prank(WHALE_ACCOUNT);
        vault.deposit(amount, WHALE_ACCOUNT);
    }

    function testDepositWithAssertions(uint256 amount) external {
        uint256 balance = USDC.balanceOf(WHALE_ACCOUNT);
        amount = bound(amount, 1, balance * 10);

        vm.prank(WHALE_ACCOUNT);
        USDC.approve(address(vault), amount);

        uint256 initialBalance = USDC.balanceOf(WHALE_ACCOUNT);
        uint256 initialVaultBalance = USDC.balanceOf(address(vault));
        uint256 initialReceiverBalance = vault.balanceOf(WHALE_ACCOUNT);

        uint256 lendLimit = vault.globalLendLimit();
        uint256 dailyDepositLimit = vault.dailyLendIncreaseLimitMin();

        if (amount > lendLimit) {
            vm.expectRevert(Constants.GlobalLendLimit.selector);
            vault.deposit(amount, WHALE_ACCOUNT);
        } else if (amount > dailyDepositLimit) {
            vm.expectRevert(Constants.DailyLendIncreaseLimit.selector);
            vault.deposit(amount, WHALE_ACCOUNT);
        } else if (amount > balance) {
            vm.expectRevert("ERC20: transfer amount exceeds balance");
            vault.deposit(amount, WHALE_ACCOUNT);
        } else {
            vm.prank(WHALE_ACCOUNT);
            uint256 shares = vault.deposit(amount, WHALE_ACCOUNT);

            uint256 finalBalance = USDC.balanceOf(WHALE_ACCOUNT);
            uint256 finalVaultBalance = USDC.balanceOf(address(vault));
            uint256 finalReceiverBalance = vault.balanceOf(WHALE_ACCOUNT);

            assertEq(finalBalance, initialBalance - amount, "Incorrect final balance after deposit");
            assertEq(finalVaultBalance, initialVaultBalance + amount, "Incorrect vault balance after deposit");
            assertEq(finalReceiverBalance, initialReceiverBalance + shares, "Incorrect shares minted to receiver");
        }
    }

    function testMintLimits(uint256 shares) external {
        shares = bound(shares, 1, type(uint128).max);

        vm.startPrank(WHALE_ACCOUNT);
        uint256 assets = vault.previewMint(shares);
        USDC.approve(address(vault), assets);

        uint256 initialBalance = USDC.balanceOf(WHALE_ACCOUNT);
        uint256 initialVaultBalance = USDC.balanceOf(address(vault));
        uint256 initialReceiverBalance = vault.balanceOf(WHALE_ACCOUNT);

        uint256 lendLimit = vault.globalLendLimit();
        uint256 dailyDepositLimit = vault.dailyLendIncreaseLimitMin();

        if (assets > lendLimit) {
            vm.expectRevert(Constants.GlobalLendLimit.selector);
            vault.mint(shares, WHALE_ACCOUNT);
        } else if (assets > dailyDepositLimit) {
            vm.expectRevert(Constants.DailyLendIncreaseLimit.selector);
            vault.mint(shares, WHALE_ACCOUNT);
        } else if (assets > initialBalance) {
            vm.expectRevert("ERC20: transfer amount exceeds balance");
            vault.mint(shares, WHALE_ACCOUNT);
        } else {
            uint256 mintedAssets = vault.mint(shares, WHALE_ACCOUNT);

            uint256 finalBalance = USDC.balanceOf(WHALE_ACCOUNT);
            uint256 finalVaultBalance = USDC.balanceOf(address(vault));
            uint256 finalReceiverBalance = vault.balanceOf(WHALE_ACCOUNT);

            assertEq(finalBalance, initialBalance - assets, "Incorrect final balance after mint");
            assertEq(finalVaultBalance, initialVaultBalance + assets, "Incorrect vault balance after mint");
            assertEq(finalReceiverBalance, initialReceiverBalance + shares, "Incorrect shares minted to receiver");
            assertEq(mintedAssets, assets, "Incorrect assets used to mint shares");
        }
    }

    function testFuzzCollateralValueLimit(uint256 borrowAmount, uint256 repayAmount) external {
        _setupBasicLoan(false);
        vault.setTokenConfig(address(DAI), uint32(Q32 * 9 / 10), uint32(Q32 / 10)); // max 10% debt for DAI

        (,, uint192 totalDebtShares) = vault.tokenConfigs(address(DAI));
        assertEq(totalDebtShares, 0);
        (,, totalDebtShares) = vault.tokenConfigs(address(USDC));
        assertEq(totalDebtShares, 0);

        borrowAmount = bound(borrowAmount, 1, 800000);
        vm.prank(TEST_NFT_ACCOUNT);
        vault.borrow(TEST_NFT, borrowAmount);

        (,, totalDebtShares) = vault.tokenConfigs(address(DAI));
        assertEq(totalDebtShares, borrowAmount);
        (,, totalDebtShares) = vault.tokenConfigs(address(USDC));
        assertEq(totalDebtShares, borrowAmount);

        uint256 extraBorrowAmount = 200001;
        vm.expectRevert(Constants.CollateralValueLimit.selector);
        vm.prank(TEST_NFT_ACCOUNT);
        vault.borrow(TEST_NFT, extraBorrowAmount);

        repayAmount = bound(repayAmount, 800000, 1100000);
        vm.prank(TEST_NFT_ACCOUNT);
        USDC.approve(address(vault), repayAmount);

        (uint256 debtShares) = vault.loans(TEST_NFT);
        assertEq(debtShares, borrowAmount);

        vm.prank(TEST_NFT_ACCOUNT);
        vault.repay(TEST_NFT, debtShares, true);

        (,, totalDebtShares) = vault.tokenConfigs(address(DAI));
        assertEq(totalDebtShares, 0);
        (,, totalDebtShares) = vault.tokenConfigs(address(USDC));
        assertEq(totalDebtShares, 0);
    }

    function testFuzzFreeLiquidation(uint256 depositAmount, uint256 borrowAmount) external {
        // lend USDC
        depositAmount = bound(depositAmount, 10000000, 10000000); 
        _deposit(depositAmount, WHALE_ACCOUNT);

        // add collateral
        vm.prank(TEST_NFT_DAI_WETH_ACCOUNT);
        NPM.approve(address(vault), TEST_NFT_DAI_WETH);
        vm.prank(TEST_NFT_DAI_WETH_ACCOUNT);
        vault.create(TEST_NFT_DAI_WETH, TEST_NFT_DAI_WETH_ACCOUNT);

        (uint256 debt, uint256 fullValue, uint256 collateralValue, uint256 liquidationCost, uint256 liquidationValue) =
            vault.loanInfo(TEST_NFT_DAI_WETH);

        assertEq(debt, 0);
        assertEq(collateralValue, 51440078684);
        assertEq(fullValue, 57155642989);
        assertEq(liquidationCost, 0);
        assertEq(liquidationValue, 0);

        // borrow max
        borrowAmount = bound(borrowAmount, 10000000, 10000000); 
        vm.prank(TEST_NFT_DAI_WETH_ACCOUNT);
        vault.borrow(TEST_NFT_DAI_WETH, borrowAmount);

        oracle.setMaxPoolPriceDifference(type(uint16).max);

        vm.mockCall(
            CHAINLINK_DAI_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1), block.timestamp, block.timestamp, uint80(0))
        );

        vm.mockCall(
            CHAINLINK_ETH_USD,
            abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
            abi.encode(uint80(0), int256(1), block.timestamp, block.timestamp, uint80(0))
        );

        (debt, fullValue, collateralValue, liquidationCost, liquidationValue) = vault.loanInfo(TEST_NFT_DAI_WETH);
        assertEq(debt, borrowAmount);
        assertEq(collateralValue, 1);
        assertEq(fullValue, 2);
        assertEq(liquidationCost, 0);
        assertEq(liquidationValue, 2);

        vm.prank(WHALE_ACCOUNT);
        vault.liquidate(IVault.LiquidateParams(TEST_NFT_DAI_WETH, 0, 0, WHALE_ACCOUNT, "", block.timestamp));

        // all debt is payed
        assertEq(vault.loans(TEST_NFT_DAI_WETH), 0);
        assertEq(vault.debtSharesTotal(), 0);
    }

    function _setupBasicLoan(bool borrowMax) internal {
        // lend 10 USDC
        _deposit(10000000, WHALE_ACCOUNT);

        // add collateral
        vm.prank(TEST_NFT_ACCOUNT);
        NPM.approve(address(vault), TEST_NFT);
        vm.prank(TEST_NFT_ACCOUNT);
        vault.create(TEST_NFT, TEST_NFT_ACCOUNT);

        (, uint256 fullValue, uint256 collateralValue,,) = vault.loanInfo(TEST_NFT);
        assertEq(collateralValue, 8846179);
        assertEq(fullValue, 9829088);

        if (borrowMax) {
            // borrow max
            uint256 buffer = vault.BORROW_SAFETY_BUFFER_X32();
            vm.prank(TEST_NFT_ACCOUNT);
            vault.borrow(TEST_NFT, collateralValue * buffer / Q32);
        }
    }

    function _deposit(uint256 amount, address account) internal {
        vm.prank(account);
        USDC.approve(address(vault), amount);
        vm.prank(account);
        vault.deposit(amount, account);
    }
}
