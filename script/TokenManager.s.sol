// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/access/TokenManager.sol";

contract DeployTokenManager is Script {
    function run() external {
        vm.startBroadcast();

        uint256 minAuthorizations = 3;

        TokenManager tokenManager = new TokenManager(minAuthorizations);

        vm.stopBroadcast();
    }
}
