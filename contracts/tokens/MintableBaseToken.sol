// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BaseToken.sol";
import "./interfaces/IMintable.sol";

/// Msg.sender is not a valid minter
error OnlyMinter();

/// @title Vaporwave Mintable Base Token
contract MintableBaseToken is BaseToken, IMintable {
    /// Mapping of minters
    mapping(address => bool) public override isMinter;

    modifier onlyMinter() {
        if (!isMinter[msg.sender]) {
            revert OnlyMinter();
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    )
        BaseToken(_name, _symbol, _initialSupply)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /// @notice Set `_account` as a minter: `_isActive`
    /// @param _minter The account to set as minter
    /// @param _isActive True to set the account as a minter, false to remove it
    function setMinter(address _minter, bool _isActive)
        external
        override
        onlyOwner
    {
        isMinter[_minter] = _isActive;
    }

    /// @notice Mint `_amount` tokens to `_account`
    /// @param _account The account to mint tokens to
    /// @param _amount The amount of tokens to mint
    function mint(address _account, uint256 _amount)
        external
        override
        onlyMinter
    {
        _mint(_account, _amount);
    }

    /// @notice Burn `_amount` tokens from `_account`
    /// @param _account The account to burn tokens from
    /// @param _amount The amount of tokens to burn
    function burn(address _account, uint256 _amount)
        external
        override
        onlyMinter
    {
        _burn(_account, _amount);
    }
}
