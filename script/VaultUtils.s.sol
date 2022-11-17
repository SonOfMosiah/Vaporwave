// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/core/VaultUtils.sol";
import "../contracts/core/interfaces/IVault.sol";
import "../contracts/core/interfaces/IVlpManager.sol";

contract DeployVaultUtils is Script {
    function run() external {
        vm.startBroadcast();

        IVault vault = IVault(0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115);
        IVlpManager vlpManager = IVlpManager(
            0x9E45785c5D34BEeF227AD0A6ff8ee4Fd06e00F8b
        );

        VaultUtils vaultUtils = new VaultUtils(vault, vlpManager);

        vm.stopBroadcast();
    }
}
