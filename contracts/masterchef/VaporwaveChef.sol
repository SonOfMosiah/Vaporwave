// SPDX-License-Identifier: MIT
//  1. Determine bonus system -> user should get 100% bonus on pool after 365 days of not withdrawing
//  withdraws should reduce their bonus
//  2. Dual Rewarder contract -> when a user claims from this masterchef, they should also get their dual rewards.
//  Hopefully we can use the same dual rewarder.
//  VWAVE + VLP will be rewarded with esVWAVE
//  3. ETH measurements
//  We need a guaranteed amount each interval.
//  User's reward amounts must not exceed each interval.
//  As bonus amounts increase, it should increase user weights in that pool.
//  But each interval should predetermine how much each pool is guaranteed.
//  'unclaimed' WETH can be carried over to the next interval

// Users deposit esVWAVE and VWAVE to receive WETH rewards

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IVaporwaveChef.sol";

/// @notice This contract is used to distribute rewards to Vaporwave Stakers
/// <3 Aurora
/// @title Vaporwave MasterChef
/// @author Alta Web3 Labs
contract VaporwaveMasterChef is IVaporwaveMasterChef, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt
    }

    /// @notice Info of each pool
    /// `allocPoint` Allocation points assigned to this pool. WETH to distribute per block
    /// `lastRewardBlock` Last block number that WETH distribution occurs
    /// `depositFeeBP` The deposit fee
    struct PoolInfo {
        IERC20 asset;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 depositFeeBP;
    }

    /// @notice Divisor for basis points calculations
    /// @return The divisor for basis points calculations (10_000)
    uint256 public constant BASIS_POINTS_DIVISOR = 10_000; // 10,000

    /// @notice The Max Deposit Fee BP
    /// @return The Max Deposit Fee BP (10,000 = 10%)
    uint256 public constant MAX_DEPOSIT_FEE_BP = 1_000; // 10%

    /// @notice Mapping of last distribution times for each reward token
    /// @return The timestamp of the last distribution for each reward token
    mapping(address => uint256) public lastDistributionTime;

    /// @notice Total allocation points. Must be the sum of all allocation points in all pools
    /// @return The total allocation points
    uint256 public totalAllocPoint;

    /// @notice The block number this contract launched
    /// @return The block number this contract launched
    uint256 public startBlock;

    /// @notice Address to receive fees
    address public feeAddress;

    /// @notice Array of information for each pool
    PoolInfo[] public poolInfo;

    /// @notice Array of addresses of reward tokens
    address[] public rewardTokens;

    /// @notice Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Mapping of tokens that have existing pools
    /// @return If a pool exists for the token
    mapping(address => bool) public poolExistence;

    /// @notice Mapping of reward tokens
    /// @return If a token is a reward token
    mapping(address => bool) public isRewardToken;

    /// @notice Mapping of tokens to pool ID
    /// @return The pid for the LP token
    mapping(address => uint256) public poolIdForLpAddress;

    /// @notice Mapping of users to their referrals
    /// @return An array of referred addresses
    mapping(address => address[]) public referrals;

    /// @notice Mapping of unclaimed reward tokens
    /// @return The amount of unclaimed reward tokens
    mapping(address => uint256) public unclaimedRewards;

    /// @notice Mapping of pool rewards per share by token
    /// @return The amount of pool rewards per share by token
    mapping(uint256 => mapping(address => uint256)) public accRewardsPerShare;

    /// @notice Mapping of user reward debt by token
    /// @return The amount of user reward debt by token
    mapping(uint256 => mapping(address => mapping(address => uint256)))
        public userRewardDebt;

    constructor(uint256 _startBlock) {
        startBlock = _startBlock;
    }

    /// @notice Deposit `_rewardToken` tokens to be distributed as rewards to pool lp shares
    /// @dev This function can be called for any token that is accepted as a reward
    function distributeRewards(address _rewardToken, uint256 _amount) external {
        if (!isRewardToken[_rewardToken]) {
            revert InvalidRewardToken();
        }
        // Transfer _amount reward token to this contract
        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        lastDistributionTime[_rewardToken] = block.timestamp;

        (uint256 newRewards, ) = _getNewRewards(_rewardToken);

        // Iterate through each pool
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];

            uint256 lpSupply = pool.asset.balanceOf(address(this));

            // get pool's allocation percentage
            uint256 poolAmount = (newRewards * pool.allocPoint) /
                totalAllocPoint;

            accRewardsPerShare[pid][_rewardToken] +=
                (poolAmount * 1e12) /
                lpSupply;
        }
        emit DistributeRewards(_rewardToken, _amount);
    }

    /// @notice Deposit LP tokens to VaporwaveChef for WETH allocation
    /// @dev Emits a `deposit` event
    /// @param _pid The ID of the pool to deposit to
    /// @param _amount The amount of LP tokens to deposit
    /// @param _referrer The referrer address
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external nonReentrant {
        if (_amount == 0) {
            revert InvalidAmount();
        }
        updatePool(_pid);

        if (_referrer == msg.sender) {
            revert SelfReferral();
        }

        if (_referrer != address(0)) {
            referrals[_referrer].push(msg.sender); // record the referral
            emit Referral(_referrer, msg.sender);
        }

        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            _claimAll(_pid, msg.sender);
        }

        // account for transfer tax
        uint256 amountBefore = pool.asset.balanceOf(address(this));

        // Transfer assets to this contract
        pool.asset.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amountAfter = pool.asset.balanceOf(address(this));
        _amount = amountAfter - amountBefore; // Transferred amount accounting for transfer tax

        if (pool.depositFeeBP > 0) {
            uint256 depositFee = (_amount * pool.depositFeeBP) /
                BASIS_POINTS_DIVISOR;
            pool.asset.safeTransfer(feeAddress, depositFee);
            user.amount += (_amount - depositFee);
        } else {
            user.amount += _amount;
        }

        uint256 length = poolInfo.length;
        for (uint256 rtid = 0; rtid < length; ++rtid) {
            address rewardToken = rewardTokens[rtid];
            uint256 rewardsPerShare = accRewardsPerShare[_pid][rewardToken];
            userRewardDebt[_pid][msg.sender][rewardToken] =
                (user.amount * rewardsPerShare) /
                1e12;
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw LP tokens from MasterChef
    /// @dev Emits a `Withdraw` event
    /// @param _pid The ID of the pool to withdraw from
    /// @param _amount The amount of LP tokens to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (_amount > user.amount) {
            revert InvalidWithdrawAmount();
        }
        updatePool(_pid);
        _claimAll(_pid, msg.sender);

        if (_amount > 0) {
            user.amount -= _amount;
            pool.asset.safeTransfer(address(msg.sender), _amount);
        }

        uint256 length = rewardTokens.length;
        for (uint256 rtid = 0; rtid < length; ++rtid) {
            address rewardToken = rewardTokens[rtid];
            userRewardDebt[_pid][msg.sender][rewardToken] =
                (user.amount * accRewardsPerShare[_pid][rewardToken]) /
                1e12;
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Add a new lp to the pool
    /// @dev DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param _allocPoint The allocation point of the LP token.
    /// @param _asset The LP token address.
    /// @param _depositFeeBP The deposit fee in basis points.
    /// @param _withUpdate True if all pools should be updated, false otherwise
    function add(
        uint256 _allocPoint,
        address _asset,
        uint256 _depositFeeBP,
        bool _withUpdate
    ) external onlyOwner {
        if (_allocPoint == 0) {
            revert InvalidAllocationPoint();
        }

        if (_depositFeeBP > MAX_DEPOSIT_FEE_BP) {
            revert InvalidDepositFee();
        }

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint += _allocPoint;
        poolIdForLpAddress[_asset] = poolInfo.length;
        poolInfo.push(
            PoolInfo({
                asset: IERC20(_asset),
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                depositFeeBP: _depositFeeBP
            })
        );
        poolExistence[_asset] = true;
    }

    // Update the given pool's WETH allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint - prevAllocPoint + _allocPoint;
        }
    }

    /// @notice Get the length of the poolInfo array
    /// @return The length of the poolInfo array
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Get the user's current pending WETH
    /// @param _pid The pool id
    /// @param _user The user's address
    /// @return userPendingRewards An array of pending rewards for each reward token
    function pendingRewards(uint256 _pid, address _user)
        external
        view
        returns (uint256[] memory userPendingRewards)
    {
        // _updateUserMultiplier(_pid, _user);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        //  get total asset balance in pool
        uint256 lpSupply = pool.asset.balanceOf(address(this));

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 length = rewardTokens.length;
            for (uint256 rtid = 0; rtid < length; ++rtid) {
                address rewardToken = rewardTokens[rtid];
                // get total reward tokens accumulated per share of pool
                uint256 rewardsPerShare = accRewardsPerShare[_pid][rewardToken];
                uint256 rewardDebt = userRewardDebt[_pid][_user][rewardToken];

                (uint256 newRewards, ) = _getNewRewards(rewardToken);
                if (newRewards > 0) {
                    uint256 reward = (newRewards * pool.allocPoint) /
                        totalAllocPoint;

                    rewardsPerShare += ((reward * 1e12) / lpSupply);
                }

                uint256 pending = ((user.amount * rewardsPerShare) / 1e12) -
                    rewardDebt;
                userPendingRewards[rtid] = pending;
            }
        }
        return userPendingRewards;
    }

    /// @notice Update reward variables for all pools
    /// @dev Loops through the poolInfo array. Be careful of gas spending!
    /// @dev Will revert if gas exceeds block limit;
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Update reward variables of the pool with ID `_pid` to be up-to-date
    /// @param _pid The ID of the pool to update
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.asset.balanceOf(address(this));

        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 length = rewardTokens.length;
        for (uint256 rtid = 0; rtid < length; ++rtid) {
            address rewardToken = rewardTokens[rtid];
            (uint256 newRewards, uint256 currentBalance) = _getNewRewards(
                rewardToken
            );
            unclaimedRewards[rewardToken] = currentBalance;
            if (newRewards > 0) {
                uint256 reward = (newRewards * pool.allocPoint) /
                    totalAllocPoint;
                accRewardsPerShare[_pid][rewardToken] += ((reward * 1e12) /
                    lpSupply);
            }
        }
        pool.lastRewardBlock = block.number;
    }

    /// @notice Emergency withdrawal of LP tokens from MasterChef
    /// @dev Withdraw without caring about rewards. EMERGENCY ONLY
    /// @param _pid The ID of the pool to withdraw from
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 transferAmount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.asset.safeTransfer(address(msg.sender), transferAmount);
        emit EmergencyWithdraw(msg.sender, _pid, transferAmount);
    }

    /// @notice Update the start block to `_startBlock`
    /// @param _startBlock The new start block
    function setStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
    }

    function _claimAll(uint256 _pid, address _user) internal {
        uint256 length = rewardTokens.length;
        for (uint256 rtid = 0; rtid < length; ++rtid) {
            address rewardToken = rewardTokens[rtid];
            _claim(rewardToken, _pid, _user);
        }
    }

    function _claim(
        address _rewardToken,
        uint256 _pid,
        address _user
    ) internal {
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 rewardPerShare = accRewardsPerShare[_pid][_rewardToken];
        uint256 rewardDebt = userRewardDebt[_pid][_user][_rewardToken];

        uint256 pending = ((user.amount * rewardPerShare) / 1e12) - rewardDebt;

        if (pending > 0) {
            _safeRewardTransfer(_rewardToken, msg.sender, pending);
        }
    }

    /// @dev Safe reward transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function _safeRewardTransfer(
        address _rewardToken,
        address _to,
        uint256 _amount
    ) internal {
        uint256 balance = IERC20(_rewardToken).balanceOf(address(this));
        if (_amount > balance) {
            IERC20(_rewardToken).safeTransfer(_to, balance);
        } else {
            IERC20(_rewardToken).safeTransfer(_to, _amount);
        }
    }

    function _getNewRewards(address _rewardToken)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 currentBalance = IERC20(_rewardToken).balanceOf(address(this));
        uint256 newWeth = currentBalance - unclaimedRewards[_rewardToken];
        return (newWeth, currentBalance);
    }
}
