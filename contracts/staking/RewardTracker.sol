// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";

/// Sender is not a valid handler
error InvalidHandler();
/// Allowance is less than the attempted transfer amount
error InsufficientAllowance();
/// Attempting to move more tokens than account's balace
error InsufficientBalance();
/// Token is not a valid deposit token
error InvalidDepositToken();
/// Token cannot interact with the zero address
error ZeroAddress();
/// Amount is greater than the stakedAmount or depositBalance
error InvalidAmount();
/// Amount must be greater than 0
error ZeroAmount();
/// Action is not enabled in private staking made
error ActionNotEnabled();
/// Contract is already initialized
error AlreadyInitialized();

/// @title Vaporwave Reward Tracker
contract RewardTracker is IERC20, ReentrancyGuard, IRewardTracker, Ownable {
    using SafeERC20 for IERC20;

    /// Helper to avoid truncations errors in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;
    /// Helper to avoid truncation errors in calculations
    uint128 public constant PRECISION = 1e30;

    /// True if the contract is initialized
    bool public isInitialized;

    /// The distributor address
    address public distributor;
    /// Mapping of deposit tokens
    mapping(address => bool) public isDepositToken;
    /// Mapping of user deposit balances
    mapping(address => mapping(address => uint256))
        public
        override depositBalances;
    /// Mapping of total deposit supplies
    mapping(address => uint256) public totalDepositSupply;

    /// The token nome
    string public name;
    /// The token symbol
    string public symbol;
    /// The token total supply
    uint256 public override totalSupply;
    /// Mapping of user token balances
    mapping(address => uint256) public balances;
    /// Mapping of user approved allowances
    mapping(address => mapping(address => uint256)) public allowances;

    /// The cumulative reward per token
    uint256 public cumulativeRewardPerToken;
    /// Mapping of user staked amounts
    mapping(address => uint256) public override stakedAmounts;
    /// Mapping of user claimable rewards
    mapping(address => uint256) public claimableReward;
    /// Mapping of previous cumulated rewards per token
    mapping(address => uint256) public previousCumulatedRewardPerToken;
    /// Mapping of cumulative rewards
    mapping(address => uint256) public override cumulativeRewards;
    /// Mapping of average staked amounts
    mapping(address => uint256) public override averageStakedAmounts;

    /// True if contract is in private transfer mode
    bool public inPrivateTransferMode;
    /// True if contract is in private staking mode
    bool public inPrivateStakingMode;
    /// True if contract is in private claiming mode
    bool public inPrivateClaimingMode;
    /// Mapping of valid handlers
    mapping(address => bool) public isHandler;

    /// @notice Emitted when rewards are claimed
    /// @param receiver The address of the receiver
    /// @param amount The amount of tokens claimed
    event Claim(address receiver, uint256 amount);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /// @notice Initializes the contract
    /// @param _depositTokens An array of deposit token addresses
    /// @param _distributor The distributor address
    function initialize(address[] memory _depositTokens, address _distributor)
        external
        onlyOwner
    {
        if (isInitialized) {
            revert AlreadyInitialized();
        }
        isInitialized = true;

        for (uint256 i = 0; i < _depositTokens.length; i++) {
            address depositToken = _depositTokens[i];
            isDepositToken[depositToken] = true;
        }

        distributor = _distributor;
    }

    /// @notice Set `_depositToken` as a deposit token: `_isDepositToken`
    /// @param _depositToken The deposit token address
    /// @param _isDepositToken True to add the address as a deposit token, false to remove it
    function setDepositToken(address _depositToken, bool _isDepositToken)
        external
        onlyOwner
    {
        isDepositToken[_depositToken] = _isDepositToken;
    }

    /// @notice Set the contract to private transfer mode: `_inPrivateTransferMode`
    /// @param _inPrivateTransferMode True to enable private transfer mode, false to disable it
    function setInPrivateTransferMode(bool _inPrivateTransferMode)
        external
        onlyOwner
    {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    /// @notice Set the contract to private staking mode: `_inPrivateStakingMode`
    /// @param _inPrivateStakingMode True to enable private staking mode, false to disable it
    function setInPrivateStakingMode(bool _inPrivateStakingMode)
        external
        onlyOwner
    {
        inPrivateStakingMode = _inPrivateStakingMode;
    }

    /// @notice Set the contract to private claiming mode: `_inPrivateClaimingMode`
    /// @param _inPrivateClaimingMode True to enable private claiming mode, false to disable it
    function setInPrivateClaimingMode(bool _inPrivateClaimingMode)
        external
        onlyOwner
    {
        inPrivateClaimingMode = _inPrivateClaimingMode;
    }

    /// @notice Set `_handler` as a handler: `_isActive`
    /// @param _handler The handler address
    /// @param _isActive True to add the address as a handler, false to remove it
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    /// @notice Withdraw tokens to `_account`
    /// @dev to help users who accidentally send their tokens to this contract
    /// @param _token The address of the token to withdraw
    /// @param _account The address of the account to receive the tokens
    /// @param _amount T
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    /// @notice Stake `_amount` of `_token` tokens
    /// @param _depositToken The address of the token to stake
    /// @param _amount The amount to stake
    function stake(address _depositToken, uint256 _amount)
        external
        override
        nonReentrant
    {
        if (inPrivateStakingMode) {
            revert ActionNotEnabled();
        }
        _stake(msg.sender, msg.sender, _depositToken, _amount);
    }

    /// @notice Stake `_amount` of `_token` tokens for `_account`
    /// @param _fundingAccount The account that is funding the stake
    /// @param _account The address of the account to stake
    /// @param _depositToken The address of the token to stake
    /// @param _amount The amount to stake
    function stakeForAccount(
        address _fundingAccount,
        address _account,
        address _depositToken,
        uint256 _amount
    ) external override nonReentrant {
        _validateHandler();
        _stake(_fundingAccount, _account, _depositToken, _amount);
    }

    /// @notice Unstake `_amount` of `_token` tokens
    /// @param _depositToken The address of the token to unstake
    /// @param _amount The amount to unstake
    function unstake(address _depositToken, uint256 _amount)
        external
        override
        nonReentrant
    {
        if (inPrivateStakingMode) {
            revert ActionNotEnabled();
        }
        _unstake(msg.sender, _depositToken, _amount, msg.sender);
    }

    /// @notice Unstake `_amount` of `_token` tokens for `_account`
    /// @param _account The address of the account to unstake
    /// @param _depositToken The address of the token to unstake
    /// @param _amount The amount to unstake
    /// @param _receiver The address of the account to receive the tokens
    function unstakeForAccount(
        address _account,
        address _depositToken,
        uint256 _amount,
        address _receiver
    ) external override nonReentrant {
        _validateHandler();
        _unstake(_account, _depositToken, _amount, _receiver);
    }

    /// @notice Transfer `_amount` tokens to `_receiver`
    /// @param _recipient The address to receive the tokens
    /// @param _amount The amount of tokens to transfer
    /// @return Whether the transfer was successful
    function transfer(address _recipient, uint256 _amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    /// @notice Transfer `_amount` tokens from `_sender` to `_receiver`
    /// @param _sender The address of the sender
    /// @param _recipient The address to receive the tokens
    /// @param _amount The amount of tokens to transfer
    /// @return Whether the transfer was successful
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
    /// @param _spender The address of the spender
    /// @param _amount The amount of tokens to approve
    /// @return Whether the approval was successful
    function approve(address _spender, uint256 _amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    /// @notice Update rewards
    function updateRewards() external override nonReentrant {
        _updateRewards(address(0));
    }

    /// @notice Claim rewards
    /// @param _receiver The address of the account to receive the tokens
    /// @return The amount of tokens claimed
    function claim(address _receiver)
        external
        override
        nonReentrant
        returns (uint256)
    {
        if (inPrivateClaimingMode) {
            revert ActionNotEnabled();
        }
        return _claim(msg.sender, _receiver);
    }

    /// @notice Claim rewards for `_account`
    /// @param _account The address of the account to claim tokens for
    /// @param _receiver The address of the account to receive the tokens
    /// @return The amount of tokens claimed
    function claimForAccount(address _account, address _receiver)
        external
        override
        nonReentrant
        returns (uint256)
    {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    /// @notice Get the token balance of `_account`
    /// @param _account The address of the account to get the balance of
    /// @return The token balance of `_account`
    function balanceOf(address _account)
        external
        view
        override
        returns (uint256)
    {
        return balances[_account];
    }

    /// @notice Get the allowance of `_spender` for `_owner`
    /// @param _owner The address of the token owner
    /// @param _spender The address of the spender
    /// @return The allowance of `_spender` for `_owner`
    function allowance(address _owner, address _spender)
        external
        view
        override
        returns (uint256)
    {
        return allowances[_owner][_spender];
    }

    /// @notice Get the tokens per interval
    /// @return The tokens per interval
    function tokensPerInterval() external view override returns (uint256) {
        return IRewardDistributor(distributor).tokensPerInterval();
    }

    /// @notice Get the token decimals (18)
    /// @return The token decimals (18)
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Get the claimable amount of tokens for `_account`
    /// @param _account The address to query for the claimable amount of tokens
    /// @return The claimable amount of tokens for `_account`
    function claimable(address _account)
        public
        view
        override
        returns (uint256)
    {
        uint256 stakedAmount = stakedAmounts[_account];
        if (stakedAmount == 0) {
            return claimableReward[_account];
        }
        uint256 supply = totalSupply;
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards() * PRECISION;
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken +
            (pendingRewards / supply);
        return
            claimableReward[_account] +
            ((stakedAmount *
                (nextCumulativeRewardPerToken -
                    previousCumulatedRewardPerToken[_account])) / PRECISION);
    }

    /// @notice Get the reward token
    /// @return The reward token address
    function rewardToken() public view returns (address) {
        return IRewardDistributor(distributor).rewardToken();
    }

    function _mint(address _account, uint256 _amount) internal {
        if (_account == address(0)) {
            revert ZeroAddress();
        }

        totalSupply += _amount;
        balances[_account] += _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        if (_account == address(0)) {
            revert ZeroAddress();
        }

        if (balances[_account] < _amount) {
            revert InsufficientBalance();
        }

        unchecked {
            balances[_account] -= _amount;
        }

        totalSupply -= _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _claim(address _account, address _receiver)
        private
        returns (uint256)
    {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken()).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
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
            _validateHandler();
        }

        if (balances[_sender] < _amount) {
            revert InsufficientBalance();
        }

        unchecked {
            balances[_sender] -= _amount;
        }

        balances[_recipient] += _amount;

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

    function _stake(
        address _fundingAccount,
        address _account,
        address _depositToken,
        uint256 _amount
    ) private {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        if (!isDepositToken[_depositToken]) {
            revert InvalidDepositToken();
        }

        IERC20(_depositToken).safeTransferFrom(
            _fundingAccount,
            address(this),
            _amount
        );

        _updateRewards(_account);

        stakedAmounts[_account] += _amount;
        depositBalances[_account][_depositToken] += _amount;
        totalDepositSupply[_depositToken] += _amount;

        _mint(_account, _amount);
    }

    function _unstake(
        address _account,
        address _depositToken,
        uint256 _amount,
        address _receiver
    ) private {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        if (!isDepositToken[_depositToken]) {
            revert InvalidDepositToken();
        }

        _updateRewards(_account);

        uint256 stakedAmount = stakedAmounts[_account];
        if (stakedAmount < _amount) {
            revert InvalidAmount();
        }

        stakedAmounts[_account] = stakedAmount - _amount;

        uint256 depositBalance = depositBalances[_account][_depositToken];
        if (depositBalance < _amount) {
            revert InvalidAmount();
        }
        depositBalances[_account][_depositToken] = depositBalance - _amount;
        totalDepositSupply[_depositToken] -= _amount;

        _burn(_account, _amount);
        IERC20(_depositToken).safeTransfer(_receiver, _amount);
    }

    function _updateRewards(address _account) private {
        uint256 blockReward = IRewardDistributor(distributor).distribute();

        uint256 supply = totalSupply;
        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        if (supply > 0 && blockReward > 0) {
            _cumulativeRewardPerToken =
                _cumulativeRewardPerToken +
                ((blockReward * PRECISION) / supply);
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (_account != address(0)) {
            uint256 stakedAmount = stakedAmounts[_account];
            uint256 accountReward = (stakedAmount *
                (_cumulativeRewardPerToken -
                    previousCumulatedRewardPerToken[_account])) / PRECISION;
            uint256 _claimableReward = claimableReward[_account] +
                accountReward;

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[
                _account
            ] = _cumulativeRewardPerToken;

            if (_claimableReward > 0 && stakedAmounts[_account] > 0) {
                uint256 nextCumulativeReward = cumulativeRewards[_account] +
                    accountReward;

                averageStakedAmounts[_account] =
                    (averageStakedAmounts[_account] *
                        cumulativeRewards[_account]) /
                    nextCumulativeReward +
                    ((stakedAmount * accountReward) / nextCumulativeReward);

                cumulativeRewards[_account] = nextCumulativeReward;
            }
        }
    }

    function _validateHandler() private view {
        if (!isHandler[msg.sender]) {
            revert InvalidHandler();
        }
    }
}
