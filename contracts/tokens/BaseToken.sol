// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IYieldTracker.sol";
import "./interfaces/IBaseToken.sol";

/// Function can only be called by an admin
error OnlyAdmin();
/// Account already marked as a non-staking account
error AccountAlreadyMarked();
/// Account not marked as a non-staking account
error AccountNotMarked();
/// Sender is not a valid handler
error InvalidHandler();
/// Allowance is less than the attempted transfer amount
error InsufficientAllowance();
/// Attempting to move more tokens than account's balace
error InsufficientBalance();
/// Token cannot interact with the zero address
error ZeroAddress();

/// @title Vaporwave Base Token
contract BaseToken is IERC20, IBaseToken, Ownable {
    using SafeERC20 for IERC20;

    /// True if contract is in private transfer mode
    bool public inPrivateTransferMode;

    /// The token name
    string public name;
    /// The token symbol
    string public symbol;

    /// The total supply
    uint256 public override totalSupply;
    /// The non-staked supply
    uint256 public nonStakingSupply;

    /// Mapping of user token balances
    mapping(address => uint256) public balances;
    /// Mapping of user approved allowances
    mapping(address => mapping(address => uint256)) public allowances;

    /// Array of yield trackers
    address[] public yieldTrackers;
    /// Mapping of non-staking accounts
    mapping(address => bool) public nonStakingAccounts;
    /// Mapping of admins
    mapping(address => bool) public admins;
    /// Mapping of handlers
    mapping(address => bool) public isHandler;

    modifier onlyAdmin() {
        if (!admins[msg.sender]) {
            revert OnlyAdmin();
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initialSupply);
    }

    /// @notice Set the token name and symbol
    /// @param _name The new name of the token
    /// @param _symbol The new symbol of the token
    function setInfo(string memory _name, string memory _symbol)
        external
        onlyOwner
    {
        name = _name;
        symbol = _symbol;
    }

    /// @notice Set the array of yield trackers
    /// @param _yieldTrackers The array of yield trackers
    function setYieldTrackers(address[] memory _yieldTrackers)
        external
        onlyOwner
    {
        yieldTrackers = _yieldTrackers;
    }

    /// @notice Add `_account` as an admin
    /// @param _account The account to add as an admin
    function addAdmin(address _account) external onlyOwner {
        admins[_account] = true;
    }

    /// @notice Remove `_account` as an admin
    /// @param _account The account to remove as an admin
    function removeAdmin(address _account) external override onlyOwner {
        admins[_account] = false;
    }

    /// @notice Withdraw tokens to `_account`
    /// @dev to help users who accidentally send their tokens to this contract
    /// @param _token The address of the token to withdraw
    /// @param _account The address of the account to receive the tokens
    /// @param _amount The amount of tokens to withdraw
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external override onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    /// @notice Set the contract in private transfer mode: `_inPrivateTransferMode`
    /// @param _inPrivateTransferMode True if contract is in private transfer mode
    function setInPrivateTransferMode(bool _inPrivateTransferMode)
        external
        override
        onlyOwner
    {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    /// @notice Set `_handler` as a handler: `_isActive`
    /// @param _handler The address of the handler
    /// @param _isActive True if handler is active, false otherwise
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    /// @notice Add a non-staking account
    /// @dev Adds the account's token balance from the non-staking supply
    /// @param _account The address of the account to add
    function addNonStakingAccount(address _account) external onlyAdmin {
        if (nonStakingAccounts[_account]) {
            revert AccountAlreadyMarked();
        }
        _updateRewards(_account);
        nonStakingAccounts[_account] = true;
        nonStakingSupply += balances[_account];
    }

    /// @notice Remove a non-staking account
    /// @dev Removes the account's token balance from the non-staking supply
    /// @param _account The address of the account to remove
    function removeNonStakingAccount(address _account) external onlyAdmin {
        if (!nonStakingAccounts[_account]) {
            revert AccountNotMarked();
        }
        _updateRewards(_account);
        nonStakingAccounts[_account] = false;
        nonStakingSupply -= balances[_account];
    }

    function recoverClaim(address _account, address _receiver)
        external
        onlyAdmin
    {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(_account, _receiver);
        }
    }

    function claim(address _receiver) external {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(msg.sender, _receiver);
        }
    }

    /// @notice Transfer `_amount` tokens to `_recipient`
    /// @param _recipient The address to receive the tokens
    /// @param _amount The amount to transfer
    /// @return Whether the transfer was successful or not
    function transfer(address _recipient, uint256 _amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @notice Transfer `_amount` tokens from `_sender` to `_recipient`
    /// @param _sender The address of the sender
    /// @param _recipient The address to receive the tokens
    /// @param _amount The amount to transfer
    /// @return Whether the transfer was successful or not
    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }
        if (allowances[_sender][msg.sender] < _amount) {
            revert InsufficientAllowance();
        }
        unchecked {
            uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;
            _approve(_sender, msg.sender, nextAllowance);
        }
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    /// @notice Approve `_spender` to transfer `_amount` tokens
    /// @param _spender The address that is allowed to spend the tokens
    /// @param _amount The amount of tokens approved
    /// @return Whether the approval was successful
    function approve(address _spender, uint256 _amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @notice Get the total amount staked
    /// @return The total amount staked
    function totalStaked() external view override returns (uint256) {
        return totalSupply - nonStakingSupply;
    }

    /// @notice Get the token balance of `_account`
    /// @param _account The address to query for the token balance
    /// @return The token balance of `_account`
    function balanceOf(address _account)
        external
        view
        override
        returns (uint256)
    {
        return balances[_account];
    }

    /// @notice Get the staked token balance of `_account`
    /// @param _account The address to query for the staked token balance
    /// @return The staked token balance of `_account`
    function stakedBalance(address _account)
        external
        view
        override
        returns (uint256)
    {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balances[_account];
    }

    /// @notice Get the allowance of `_spender` for `_owner`
    /// @param _owner The address that owns the tokens
    /// @param _spender The address that is allowed to spend the tokens
    /// @return The amount of tokens that `_spender` is allowed to spend for `_owner`
    function allowance(address _owner, address _spender)
        external
        view
        override
        returns (uint256)
    {
        return allowances[_owner][_spender];
    }

    /// @notice Get the token decimals (18)
    /// @return The token decimals (18)
    function decimals() external pure returns (uint8) {
        return 18;
    }

    function _mint(address _account, uint256 _amount) internal {
        if (_account == address(0)) {
            revert ZeroAddress();
        }

        _updateRewards(_account);

        totalSupply += _amount;
        balances[_account] += _amount;

        if (nonStakingAccounts[_account]) {
            nonStakingSupply += _amount;
        }

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        if (_account == address(0)) {
            revert ZeroAddress();
        }

        _updateRewards(_account);

        if (balances[_account] < _amount) {
            revert InsufficientBalance();
        }

        unchecked {
            balances[_account] -= _amount;
        }

        totalSupply -= _amount;

        if (nonStakingAccounts[_account]) {
            nonStakingSupply -= _amount;
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        if (_sender == address(0) || _recipient == address(0)) {
            revert ZeroAddress();
        }

        if (inPrivateTransferMode) {
            if (!isHandler[msg.sender]) {
                revert InvalidHandler();
            }
        }

        _updateRewards(_sender);
        _updateRewards(_recipient);

        if (balances[_sender] < _amount) {
            revert InsufficientBalance();
        }

        unchecked {
            balances[_sender] -= _amount;
        }

        balances[_recipient] += _amount;

        if (nonStakingAccounts[_sender]) {
            nonStakingSupply -= _amount;
        }
        if (nonStakingAccounts[_recipient]) {
            nonStakingSupply += _amount;
        }

        emit Transfer(_sender, _recipient, _amount);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        if (_owner == address(0) || _spender == address(0)) {
            revert ZeroAddress();
        }

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _updateRewards(address _account) private {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).updateRewards(_account);
        }
    }
}
