// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/oracle/FastPriceEvents.sol";

contract DeployFastPriceEvents is Script {
    function run() external {
        vm.startBroadcast();

        FastPriceEvents fastPriceEvents = new FastPriceEvents();

        vm.stopBroadcast();
    }
}
