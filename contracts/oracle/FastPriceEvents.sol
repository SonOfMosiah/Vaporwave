// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IFastPriceEvents.sol";

/// @title Vaporwave Fast Price Events Oracle
contract FastPriceEvents is IFastPriceEvents, Ownable {
    mapping(address => bool) public isPriceFeed;
    event PriceUpdate(address token, uint256 price, address priceFeed);

    /// @notice Mark an address as a price feed
    /// @param _priceFeed Address of the price feed to mark
    /// @param _isPriceFeed True if the address is a price feed, false otherwise
    function setIsPriceFeed(address _priceFeed, bool _isPriceFeed)
        external
        onlyOwner
    {
        isPriceFeed[_priceFeed] = _isPriceFeed;
    }

    /// @notice Emit a price event
    /// @dev Can only be called by a price feed
    /// @param _token Address of the token
    /// @param _price Price of the token
    function emitPriceEvent(address _token, uint256 _price) external override {
        require(isPriceFeed[msg.sender], "FastPriceEvents: invalid sender");
        emit PriceUpdate(_token, _price, msg.sender);
    }
}
