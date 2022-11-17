// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/oracle/FastPriceFeed.sol";

contract DeployFastPriceFeed is Script {
    function run() external {
        vm.startBroadcast();

        uint256 priceDuration = 5 minutes;
        uint256 minBlockInterval = 0;
        uint256 maxDeviationBasisPoints = 250;
        address fastPriceEvents = 0x28cAC3219cDE0E7Abe91c80033B9e470740aFDe0;
        address tokenManager = 0xA03555836F2DcC37508178252F70Dd44BAFa9d02;
        address positionRouter = 0xC6ec82bA3310b250aa403EF6ae588c6f3169c062;

        FastPriceFeed fastPriceFeed = new FastPriceFeed(
            priceDuration,
            minBlockInterval,
            maxDeviationBasisPoints,
            fastPriceEvents,
            tokenManager,
            positionRouter
        );

        vm.stopBroadcast();
    }
}
