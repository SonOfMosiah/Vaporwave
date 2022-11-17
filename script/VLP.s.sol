// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/vwave/VLP.sol";

contract DeployVLP is Script {
    function run() external {
        vm.startBroadcast();

        VLP vlp = new VLP();

        vm.stopBroadcast();
    }
}
