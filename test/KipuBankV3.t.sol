// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {Oracle} from "../src/mocks/Oracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBankV3Test is Test {
    KipuBankV3 public kipuBank;
    address constant ROUTER = 0x2ca7d64A7EFE2D62A725E2B35Cf7230D6677FfEe;
    address constant USDC = 0xfC9201f4116aE6b054722E10b98D904829b469c3;
    address constant WETH = 0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91;
    address constant WHALE = 0x6a956f0AEd3b8625F20d696A5e934A5DE8C27A2C;
    address constant USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant WITHDRAWAL_LIMIT = 1000 * 10 ** 6; // 1000 USDC (6 decimals)
    uint256 constant BANK_CAP = 2_000 * 10 ** 6; // 2000 USDC (6 decimals)

    uint256 constant AMOUNT_IN = 1_000_000; // 1 USDC (6 decimals)
    uint256 constant AMOUNT_OUT_MIN = 990_000; // 0.99 USDC (6 decimals)

    address constant POL = 0xADF73ebA3Ebaa7254E859549A44c74eF7cff7501;
    address constant POL_WHALE = 0xe2cDe87f7DbaD089D7B8122E16ccA7BdB112eaaE;
    uint256 constant POL_AMOUNT = 1 * 10 ** 18; // 1 POL (18 decimals)

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL"));
        AggregatorV3Interface oracle = new Oracle();
        kipuBank = new KipuBankV3(
            oracle,
            ROUTER,
            USDC,
            WITHDRAWAL_LIMIT,
            BANK_CAP,
            USER
        );
    }

    function getFunds(uint256 amountIn) public {
        vm.startPrank(WHALE);
        IERC20(USDC).transfer(USER, amountIn);
        vm.stopPrank();
    }

    function testDepositUsdcToken() public {
        getFunds(AMOUNT_IN);
        uint256 before = IERC20(USDC).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(USDC).approve(address(kipuBank), type(uint256).max);
        kipuBank.depositToken(USDC, AMOUNT_IN, AMOUNT_OUT_MIN);

        uint256 afterBal = IERC20(USDC).balanceOf(USER);

        assertLt(afterBal, before, "USDC balance should decrease");
        vm.stopPrank();
    }

    function testDepositERC20Token() public {
        vm.startPrank(POL_WHALE);
        IERC20(POL).transfer(USER, POL_AMOUNT);
        vm.stopPrank();

        uint256 before = IERC20(POL).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(POL).approve(address(kipuBank), type(uint256).max);
        kipuBank.depositToken(POL, POL_AMOUNT, 1);

        uint256 afterBal = IERC20(POL).balanceOf(USER);

        assertLt(afterBal, before, "POL balance should decrease");
        vm.stopPrank();
    }

    function testDepositEth() public {
        uint256 before = USER.balance;
        vm.deal(USER, 0.1 ether);
        uint256 afterBal = USER.balance;

        vm.startPrank(USER);
        kipuBank.depositEth{value: afterBal}(100);

        uint256 usdcAmount = kipuBank.getUserBalance(USER);

        assertGt(usdcAmount, 0, "User vault balance should increase");
        vm.stopPrank();
    }

    function testBankCapExceededMustRevert() public {
        uint256 amountIn = 1_200_000_000; // 1200 USDC

        getFunds(amountIn);
        uint256 before = IERC20(USDC).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(USDC).approve(address(kipuBank), type(uint256).max);
        kipuBank.depositToken(USDC, amountIn, AMOUNT_OUT_MIN);

        vm.expectRevert();
        kipuBank.depositToken(USDC, amountIn, AMOUNT_OUT_MIN); // Exceeds bank cap

        vm.stopPrank();
    }

    function testWithDraw() public {
        getFunds(AMOUNT_IN);
        uint256 before = IERC20(USDC).balanceOf(USER);

        vm.startPrank(USER);
        IERC20(USDC).approve(address(kipuBank), type(uint256).max);
        kipuBank.depositToken(USDC, AMOUNT_IN, AMOUNT_OUT_MIN);
        kipuBank.withdrawUsdc(AMOUNT_IN);
        uint256 afterBal = IERC20(USDC).balanceOf(USER);

        assertEq(
            before,
            afterBal,
            "User's USDC balance should be restored after withdrawal"
        );
        vm.stopPrank();
    }

    function testGetUserBalance() public {
        getFunds(AMOUNT_IN);

        vm.startPrank(USER);
        IERC20(USDC).approve(address(kipuBank), type(uint256).max);
        kipuBank.depositToken(USDC, AMOUNT_IN, AMOUNT_OUT_MIN);
        uint256 userVaultBalance = kipuBank.getUserBalance(USER);

        assertEq(
            AMOUNT_IN,
            userVaultBalance,
            "Vault balance should match the deposited amount"
        );
        vm.stopPrank();
    }

    function testPreviewDeposit() public {
        vm.startPrank(USER);
        uint256 previewAmount = kipuBank.previewDeposit(USDC, AMOUNT_IN);

        assertEq(
            AMOUNT_IN,
            previewAmount,
            "Preview amount for USDC should be the same as input amount"
        );
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        getFunds(AMOUNT_IN);

        vm.startPrank(USER);
        kipuBank.pause();

        IERC20(USDC).approve(address(kipuBank), type(uint256).max);
        vm.expectRevert();
        kipuBank.depositToken(USDC, AMOUNT_IN, AMOUNT_OUT_MIN);

        kipuBank.unpause();

        uint256 before = IERC20(USDC).balanceOf(USER);
        kipuBank.depositToken(USDC, AMOUNT_IN, AMOUNT_OUT_MIN);
        uint256 afterBal = IERC20(USDC).balanceOf(USER);
        assertLt(afterBal, before, "USDC balance should decrease");
        vm.stopPrank();
    }
}
