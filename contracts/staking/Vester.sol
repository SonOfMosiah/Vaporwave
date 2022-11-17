// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";

/// Sender is not a handler
error InvalidHandler();
/// Cannot mint to the zero address
error InvalidMintAddress();
/// Cannot burn from the zero address
error InvalidBurnAddress();
/// Deposit amount must be greater than 0
error InvalidAmount();
/// Max vestable amount exceeded
error MaxAmountExceeded();
/// The token cannot be transferred
error CannotTransfer();

/// @title Vaporwave Vester
contract Vester is IVester, IERC20, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// The vesting duration in seconds
    uint256 public immutable vestingDuration;
    /// The escrow token address
    address public immutable esToken;
    /// The pair token address
    address public immutable pairToken;
    /// The claimable (base) token
    address public immutable claimableToken;
    /// Reward Tracker address (staked token)
    address public immutable override rewardTracker;

    /// The token name
    string public name;
    /// The token symbol
    string public symbol;

    /// Token total supply
    uint256 public override totalSupply;
    /// Pair supply
    uint256 public pairSupply;

    /// True if there is a max vestable amount
    bool public hasMaxVestableAmount;

    /// Mapping of users to their token balances
    mapping(address => uint256) public balances;
    /// Mapping of user pair amounts
    mapping(address => uint256) public override pairAmounts;
    /// Mapping of user cumulative claim amounts
    mapping(address => uint256) public override cumulativeClaimAmounts;
    /// Mapping of user claimed amounts
    mapping(address => uint256) public override claimedAmounts;
    /// Mapping of user last vesting time
    mapping(address => uint256) public lastVestingTimes;
    /// Mapping of user transferred average staked amounts
    mapping(address => uint256) public override transferredAverageStakedAmounts;
    /// Mapping of user transferred cumulative rewards
    mapping(address => uint256) public override transferredCumulativeRewards;
    /// Mapping of user cumulative reward deductions
    mapping(address => uint256) public override cumulativeRewardDeductions;
    /// Mapping of user bonus rewards
    mapping(address => uint256) public override bonusRewards;

    /// Mapping of valid handlers
    mapping(address => bool) public isHandler;

    /// @notice Emitted when tokens are claimed
    /// @param receiver The receiver of the tokens
    /// @param amount The amount of tokens claimed
    event Claim(address receiver, uint256 amount);
    /// @notice Emitted when tokens are deposited
    /// @param account The account that is depositing the tokens
    /// @param amount The amount of tokens deposited
    event Deposit(address account, uint256 amount);
    /// @notice Emitted when tokens are withdrawn
    /// @param account The account that is withdrawing the tokens
    /// @param claimedAmount The amount of tokens claimed with the withdrawal
    /// @param balance The amount of tokens remaining in the account
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);
    /// @notice Emitted when the pair token is transferred
    /// @param from The sender of the tokens
    /// @param to The recipient of the tokens
    /// @param value The amount of tokens transferred
    event PairTransfer(address indexed from, address indexed to, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _vestingDuration,
        address _esToken,
        address _pairToken,
        address _claimableToken,
        address _rewardTracker
    ) {
        name = _name;
        symbol = _symbol;

        vestingDuration = _vestingDuration;

        esToken = _esToken;
        pairToken = _pairToken;
        claimableToken = _claimableToken;

        rewardTracker = _rewardTracker;

        if (rewardTracker != address(0)) {
            hasMaxVestableAmount = true;
        }
    }

    /// @notice Set `handler` as a handler: `_isActive`
    /// @param _handler The handler address
    /// @param _isActive True if the handler is active, false otherwise
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
    }

    /// @notice Set hasMaxVestableAmount to `_hasMaxVestableAmount`
    /// @param _hasMaxVestableAmount True if the contract has a max vestable amount, false otherwise
    function setHasMaxVestableAmount(bool _hasMaxVestableAmount)
        external
        onlyOwner
    {
        hasMaxVestableAmount = _hasMaxVestableAmount;
    }

    /// @notice Deposit escrowed tokens for vested tokens
    /// @param _amount The amount of escrowed tokens to deposit
    function deposit(uint256 _amount) external nonReentrant {
        _deposit(msg.sender, _amount);
    }

    /// @notice Deposit escrowed tokens for vested tokens for `_account`
    /// @param _account The account to deposit for
    /// @param _amount The amount of escrowed tokens to deposit
    function depositForAccount(address _account, uint256 _amount)
        external
        nonReentrant
    {
        _validateHandler();
        _deposit(_account, _amount);
    }

    /// @notice Burn the vested tokens that have matured and receive the base tokens
    function claim() external nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    /// @notice Claim tokens for `_account`
    /// @param _account The account to claim for
    /// @param _receiver The receiver of the tokens
    function claimForAccount(address _account, address _receiver)
        external
        override
        nonReentrant
        returns (uint256)
    {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    /// @dev to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    /// @notice Claim matured vested tokens and withdraw remaining escrowed tokens
    function withdraw() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        _claim(account, _receiver);

        uint256 claimedAmount = cumulativeClaimAmounts[account];
        uint256 balance = balances[account];
        uint256 totalVested = balance + claimedAmount;
        if (totalVested == 0) {
            revert InvalidAmount();
        }

        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[account];
            _burnPair(account, pairAmount);
            IERC20(pairToken).safeTransfer(_receiver, pairAmount);
        }

        IERC20(esToken).safeTransfer(_receiver, balance);
        _burn(account, balance);

        delete cumulativeClaimAmounts[account];
        delete claimedAmounts[account];
        delete lastVestingTimes[account];

        emit Withdraw(account, claimedAmount, balance);
    }

    /// @notice Transfer stake values from `_sender` to `_receiver`
    /// @param _sender The sender of the stake
    /// @param _receiver The receiver of the stake
    function transferStakeValues(address _sender, address _receiver)
        external
        override
        nonReentrant
    {
        _validateHandler();

        transferredAverageStakedAmounts[
            _receiver
        ] = getCombinedAverageStakedAmount(_sender);
        transferredAverageStakedAmounts[_sender] = 0;

        uint256 transferredCumulativeReward = transferredCumulativeRewards[
            _sender
        ];
        uint256 cumulativeReward = IRewardTracker(rewardTracker)
            .cumulativeRewards(_sender);

        transferredCumulativeRewards[_receiver] =
            transferredCumulativeReward +
            cumulativeReward;
        cumulativeRewardDeductions[_sender] = cumulativeReward;
        transferredCumulativeRewards[_sender] = 0;

        bonusRewards[_receiver] = bonusRewards[_sender];
        bonusRewards[_sender] = 0;
    }

    /// @notice Set the transferred average staked amounts for `_account` to `_amount`
    /// @param _account The account to set the average staked amount for
    /// @param _amount The amount to set the average staked amount to
    function setTransferredAverageStakedAmounts(
        address _account,
        uint256 _amount
    ) external override nonReentrant {
        _validateHandler();
        transferredAverageStakedAmounts[_account] = _amount;
    }

    /// @notice Set the transferred cumulative rewards for `_account` to `_amount`
    /// @param _account The account to set the transferred cumulative reward for
    /// @param _amount The amount to set the transferred cumulative reward to
    function setTransferredCumulativeRewards(address _account, uint256 _amount)
        external
        override
        nonReentrant
    {
        _validateHandler();
        transferredCumulativeRewards[_account] = _amount;
    }

    /// @notice Set the cumulative reward deductions for `_account` to `_amount`
    /// @param _account The account to set the cumulative reward deductions for
    /// @param _amount The amount to set the cumulative reward deductions tos
    function setCumulativeRewardDeductions(address _account, uint256 _amount)
        external
        override
        nonReentrant
    {
        _validateHandler();
        cumulativeRewardDeductions[_account] = _amount;
    }

    /// @notice Set the bonus rewrds for `_account` to `_amount`
    /// @param _account The account to set the bonus rewards for
    /// @param _amount The amount to set the bonus rewards to
    function setBonusRewards(address _account, uint256 _amount)
        external
        override
        nonReentrant
    {
        _validateHandler();
        bonusRewards[_account] = _amount;
    }

    /// @notice Get the token decimals (18)
    /// @return The token decimals (18)
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Get the claimable amount for `_account`
    /// @param _account Account to query for the claimable amount
    /// @return The claimable token amount for `_account`
    function claimable(address _account)
        public
        view
        override
        returns (uint256)
    {
        uint256 amount = cumulativeClaimAmounts[_account] -
            claimedAmounts[_account];
        uint256 nextClaimable = _getNextClaimableAmount(_account);
        return amount + nextClaimable;
    }

    /// @notice Get the max vestable amount for `_account`
    /// @param _account Account to query for the max vestable amount
    /// @return The max vestable token amount for `_account`
    function getMaxVestableAmount(address _account)
        public
        view
        override
        returns (uint256)
    {
        if (!hasRewardTracker()) {
            return 0;
        }

        uint256 transferredCumulativeReward = transferredCumulativeRewards[
            _account
        ];
        uint256 bonusReward = bonusRewards[_account];
        uint256 cumulativeReward = IRewardTracker(rewardTracker)
            .cumulativeRewards(_account);
        uint256 maxVestableAmount = cumulativeReward +
            transferredCumulativeReward +
            bonusReward;

        uint256 cumulativeRewardDeduction = cumulativeRewardDeductions[
            _account
        ];

        if (maxVestableAmount < cumulativeRewardDeduction) {
            return 0;
        }

        return maxVestableAmount - cumulativeRewardDeduction;
    }

    /// @notice Get the combined average staked amount for `_account`
    /// @param _account Account to query for the combined average staked amount
    /// @return The combined average staked amount for `_account`
    function getCombinedAverageStakedAmount(address _account)
        public
        view
        override
        returns (uint256)
    {
        uint256 cumulativeReward = IRewardTracker(rewardTracker)
            .cumulativeRewards(_account);
        uint256 transferredCumulativeReward = transferredCumulativeRewards[
            _account
        ];
        uint256 totalCumulativeReward = cumulativeReward +
            transferredCumulativeReward;
        if (totalCumulativeReward == 0) {
            return 0;
        }

        uint256 averageStakedAmount = IRewardTracker(rewardTracker)
            .averageStakedAmounts(_account);
        uint256 transferredAverageStakedAmount = transferredAverageStakedAmounts[
                _account
            ];

        return
            (averageStakedAmount * cumulativeReward) /
            totalCumulativeReward +
            ((transferredAverageStakedAmount * transferredCumulativeReward) /
                totalCumulativeReward);
    }

    /// @notice Get the pair amount for `_account` with `_esAmount` escrowed tokens
    /// @param _account Account to query for the pair amount
    /// @param _esAmount The amount of escrowed tokens
    /// @return The pair token amount for `_account` with `_esAmount` escrowed tokens
    function getPairAmount(address _account, uint256 _esAmount)
        public
        view
        returns (uint256)
    {
        if (!hasRewardTracker()) {
            return 0;
        }

        uint256 combinedAverageStakedAmount = getCombinedAverageStakedAmount(
            _account
        );
        if (combinedAverageStakedAmount == 0) {
            return 0;
        }

        uint256 maxVestableAmount = getMaxVestableAmount(_account);
        if (maxVestableAmount == 0) {
            return 0;
        }

        return (_esAmount * combinedAverageStakedAmount) / maxVestableAmount;
    }

    /// @notice Get if the contract has a reward tracker
    /// @return True if the contract has a reward tracker, false otherwise
    function hasRewardTracker() public view returns (bool) {
        return rewardTracker != address(0);
    }

    /// @notice Get if the contract has a pair token
    /// @return True if the contract has a pair token, false otherwise
    function hasPairToken() public view returns (bool) {
        return pairToken != address(0);
    }

    /// @notice Get the total vested amount for `_account`
    /// @param _account Account to query for the total vested amount
    /// @return The total vested amount for `_account`
    function getTotalVested(address _account) public view returns (uint256) {
        return balances[_account] + cumulativeClaimAmounts[_account];
    }

    /// @notice Get the token balance of `_account`
    /// @param _account Account to query for the token balance
    /// @return The token balance of `_account`
    function balanceOf(address _account)
        public
        view
        override
        returns (uint256)
    {
        return balances[_account];
    }

    /// @dev Always returns 0 empty, tokens are non-transferrable
    function allowance(
        address, /* owner */
        address /* spender */
    ) public view virtual override returns (uint256) {
        return 0;
    }

    function getVestedAmount(address _account)
        public
        view
        override
        returns (uint256)
    {
        uint256 balance = balances[_account];
        uint256 cumulativeClaimAmount = cumulativeClaimAmounts[_account];
        return balance + cumulativeClaimAmount;
    }

    /// @dev Always reverts, tokens are non-transferrable
    function approve(
        address, /* spender */
        uint256 /* amount */
    ) public pure virtual override returns (bool) {
        revert CannotTransfer();
    }

    /// @dev Always reverts, tokens are non-transferrable
    function transfer(
        address, /* recipient */
        uint256 /* amount */
    ) public pure override returns (bool) {
        revert CannotTransfer();
    }

    /// @dev Always reverts, tokens are non-transferrable
    function transferFrom(
        address, /* sender */
        address, /* recipient */
        uint256 /* amount */
    ) public pure virtual override returns (bool) {
        revert CannotTransfer();
    }

    function _mint(address _account, uint256 _amount) private {
        if (_account == address(0)) {
            revert InvalidMintAddress();
        }

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _mintPair(address _account, uint256 _amount) private {
        if (_account == address(0)) {
            revert InvalidMintAddress();
        }

        pairSupply += _amount;
        pairAmounts[_account] += _amount;

        emit PairTransfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) private {
        if (_account == address(0)) {
            revert InvalidBurnAddress(); // Question: Is this needed if can't mint or transfer to zero address?
        }

        if (balances[_account] < _amount) {
            revert InvalidAmount();
        }

        unchecked {
            balances[_account] = balances[_account] - _amount;
        }

        totalSupply = totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }

    function _burnPair(address _account, uint256 _amount) private {
        if (_account == address(0)) {
            revert InvalidBurnAddress();
        }

        if (pairAmounts[_account] < _amount) {
            revert InvalidAmount();
        }

        unchecked {
            pairAmounts[_account] = pairAmounts[_account] - _amount;
        }

        pairSupply = pairSupply - _amount;

        emit PairTransfer(_account, address(0), _amount);
    }

    function _deposit(address _account, uint256 _amount) private {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        _updateVesting(_account);

        IERC20(esToken).safeTransferFrom(_account, address(this), _amount);

        _mint(_account, _amount);

        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[_account];
            uint256 nextPairAmount = getPairAmount(
                _account,
                balances[_account]
            );
            if (nextPairAmount > pairAmount) {
                uint256 pairAmountDiff = nextPairAmount - pairAmount;
                IERC20(pairToken).safeTransferFrom(
                    _account,
                    address(this),
                    pairAmountDiff
                );
                _mintPair(_account, pairAmountDiff);
            }
        }

        if (hasMaxVestableAmount) {
            uint256 maxAmount = getMaxVestableAmount(_account);
            if (getTotalVested(_account) > maxAmount) {
                revert MaxAmountExceeded();
            }
        }

        emit Deposit(_account, _amount);
    }

    /// @dev Burns the next claimable amount from `_account`
    /// @dev Burns the same amount of esToken from this contract
    function _updateVesting(address _account) private {
        uint256 amount = _getNextClaimableAmount(_account);
        // solhint-disable-next-line not-rely-on-time
        lastVestingTimes[_account] = block.timestamp;

        if (amount == 0) {
            return;
        }

        // transfer claimableAmount from balances to cumulativeClaimAmounts
        _burn(_account, amount);
        cumulativeClaimAmounts[_account] += amount;

        IMintable(esToken).burn(address(this), amount);
    }

    function _claim(address _account, address _receiver)
        private
        returns (uint256)
    {
        _updateVesting(_account);
        uint256 amount = claimable(_account); // Question what does amount equal?
        claimedAmounts[_account] = claimedAmounts[_account] + amount;
        IERC20(claimableToken).safeTransfer(_receiver, amount);
        emit Claim(_account, amount);
        return amount;
    }

    function _getNextClaimableAmount(address _account)
        private
        view
        returns (uint256)
    {
        // solhint-disable-next-line not-rely-on-time
        uint256 timeDiff = block.timestamp - lastVestingTimes[_account];

        uint256 balance = balances[_account];
        if (balance == 0) {
            return 0;
        }

        uint256 vestedAmount = getVestedAmount(_account);
        uint256 claimableAmount = (vestedAmount * timeDiff) / vestingDuration;

        if (claimableAmount < balance) {
            return claimableAmount;
        }

        return balance;
    }

    function _validateHandler() private view {
        if (!isHandler[msg.sender]) {
            revert InvalidHandler();
        }
    }
}
