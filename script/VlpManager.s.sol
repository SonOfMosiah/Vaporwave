// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/core/VlpManager.sol";

contract DeployVlpManager is Script {
    function run() external {
        vm.startBroadcast();

        address vault = address(0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115);
        address vlp = address(0xE6C27c3F6295A5b7Df0b032940de09Ee9d390043);
        uint256 cooldownDuration = 15 minutes;

        VlpManager vlpManager = new VlpManager(vault, vlp, cooldownDuration);

        vm.stopBroadcast();
    }
}
