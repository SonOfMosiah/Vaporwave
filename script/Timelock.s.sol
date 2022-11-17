// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/peripherals/Timelock.sol";

contract DeployTimelock is Script {
    function run() external {
        vm.startBroadcast();

        address admin = 0x087183a411770a645A96cf2e31fA69Ab89e22F5E;
        uint256 buffer = 1 days;
        address rewardManager = address(0);
        address tokenManager = 0xA03555836F2DcC37508178252F70Dd44BAFa9d02;
        address mintReceiver;
        uint256 maxTokenSupply = 1325e22;
        uint256 marginFeeBasisPoints = 10;
        uint256 maxMarginFeeBasisPoints = 100;

        Timelock timelock = new Timelock(
            admin,
            buffer,
            rewardManager,
            tokenManager,
            mintReceiver,
            maxTokenSupply,
            marginFeeBasisPoints,
            maxMarginFeeBasisPoints
        );

        vm.stopBroadcast();
    }
}
