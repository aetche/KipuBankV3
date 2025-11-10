// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract DeployKipuBankV3 is Script {
    function run() external returns (KipuBankV3 _kipuBank) {
        KipuBankV3 kipuBank;
        address _user = vm.envAddress("USER");
        address _router = address(0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3); // uniswapV2Router02
        address _usdc = address(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238); // usdc

        AggregatorV3Interface _ethOracle = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306
        );
        uint256 _withdrawalLimit = 5000 * 10 ** 6; // 5000 USDC (6 decimals)
        uint256 _bankCap = 10_000 * 10 ** 6; // 10,000 USDC (6 decimals)

        vm.startBroadcast();
        kipuBank = new KipuBankV3(
            _ethOracle,
            _router,
            _usdc,
            _withdrawalLimit,
            _bankCap,
            _user
        );
        vm.stopBroadcast();
    }
}
