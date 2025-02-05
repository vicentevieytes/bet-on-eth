// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {OverUnderBet} from "../src/OverUnderBet.sol";

contract DeployOverUnderBet is Script {
    function run() public {
        // ETH/USD Sepolia PriceFeed
        address priceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        uint256 betDate = block.timestamp + 10 minutes;

        vm.startBroadcast();
        OverUnderBet overUnderBet = new OverUnderBet(priceFeed, betDate);
        console.log("OverUnderBet contract address:", address(overUnderBet));

        vm.stopBroadcast();
    }
}
