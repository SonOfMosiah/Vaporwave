// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/peripherals/Reader.sol";

contract DeployReader is Script {
    function run() external {
        vm.startBroadcast();

        Reader reader = new Reader();

        vm.stopBroadcast();
    }
}
