// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/core/VaultPriceFeed.sol";

contract DeployVaultPriceFeed is Script {
    function run() external {
        vm.startBroadcast();

        VaultPriceFeed vaultPriceFeed = new VaultPriceFeed();

        vm.stopBroadcast();
    }
}
