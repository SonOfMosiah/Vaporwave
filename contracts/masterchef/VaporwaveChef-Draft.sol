// // SPDX-License-Identifier: MIT
// //  TODO:
// //  1. Determine bonus system -> user should get 100% bonus on pool after 365 days of not withdrawing
// //  withdraws should reduce their bonus
// //  2. Dual Rewarder contract -> when a user claims from this masterchef, they should also get their dual rewards.
// //  Hopefully we can use the same dual rewarder.
// //  VWAVE + VLP will be rewarded with esVWAVE
// //  3. ETH measurements
// //  We need a guaranteed amount each interval.
// //  User's reward amounts must not exceed each interval.
// //  As bonus amounts increase, it should increase user weights in that pool.
// //  But each interval should predetermine how much each pool is guaranteed.
// //  'unclaimed' WETH can be carried over to the next inerval.

// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// // This masterchef contract is used to distribute WETH to Vaporwave Stakers
// //  100% of WETH earned from our futures protocol goes back to this pool.
// //  <3 Aurora
// //
// contract VaporwaveMasterChef is Ownable, ReentrancyGuard {
//     using SafeMath for uint256;
//     using SafeERC20 for IERC20;

//     // Info of each user.
//     struct UserInfo {
//         uint256 amount; // How many LP tokens the user has provided.
//         uint256 rewardDebt; // Reward debt. See explanation below.
//         uint256 currentBonusMultiplier; // Current bonus multiplier for not withdrawing
//         uint256 lastRewardTimestamp; // Last time user staked/harvested TODO: remove?
//         uint256 poolEntranceTime; //  unix timestamp of entrance in pool
//     }
//     //
//     // We do some fancy math here. Basically, any point in time, the amount of CAKEs
//     // entitled to a user but is pending to be distributed is:
//     //
//     //   pending reward = (user.amount * pool.accCakePerShare) - user.rewardDebt
//     //
//     // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
//     //   1. The pool's `accCakePerShare` (and `lastRewardBlock`) gets updated.
//     //   2. User receives the pending reward sent to his/her address.
//     //   3. User's `amount` gets updated.
//     //   4. User's `rewardDebt` gets updated.

//     // Info of each pool.
//     struct PoolInfo {
//         IERC20 asset; // Address of token contract.
//         uint256 allocPoint; // How many allocation points assigned to this pool. ETH to distribute per block.
//         uint256 lastRewardBlock; // Last block number that ETH distribution occurs.
//         uint256 accWETHPerShare; // Accumulated WETH per share, times 1e12. See below.
//         uint256 totalWETHPerInterval; //  establish total allocation of WETH for pool per interval.
//     }

//     // ETH
//     address public constant WETH = address(0); //TODO
//     // Dev address.
//     address public devAddress;
//     // Bonus muliplier for early ETH makers.
//     uint256 public constant BONUS_MULTIPLIER = 1;
//     // ETH tokens created per block.
//     uint256 public wethPerBlock;
//     // Info of each pool.
//     PoolInfo[] public poolInfo;
//     // Info of each user that stakes LP tokens.
//     mapping(uint256 => mapping(address => UserInfo)) public userInfo;

//     // Total allocation points. Must be the sum of all allocation points in all pools.
//     uint256 public totalAllocPoint = 0;
//     // The block number when ETH mining starts.
//     uint256 public startBlock;
//     // Total locked up rewards
//     uint256 public totalLockedUpRewards;

//     // seconds to reach 100% multiplier  => 1 year
//     uint256 public constant BASIS_POINTS_DIVISOR = 10000;
//     uint256 public constant BONUS_DURATION = 365 days; //  31536000
//     uint256 public bonusMultiplierBasisPoints = 10000; //  10000
//     //  https://snowtrace.io/address/0x23208b91a98c7c1cd9fe63085bff68311494f193#readContract

//     // Pool Exists Mapper
//     mapping(IERC20 => bool) public poolExistence;
//     // Pool ID Tracker Mapper
//     mapping(IERC20 => uint256) public poolIdForLpAddress;

//     event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
//     event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
//     event EmergencyWithdraw(
//         address indexed user,
//         uint256 indexed pid,
//         uint256 amount
//     );
//     event NewFundingInterval(
//         address indexed funder,
//         uint256 indexed intervalFunding
//     );

//     event EmissionRateUpdated(
//         address indexed caller,
//         uint256 previousAmount,
//         uint256 newAmount
//     );

//     constructor(uint256 _startBlock) public {
//         startBlock = _startBlock;
//         devAddress = msg.sender;
//     }

//     function poolLength() external view returns (uint256) {
//         return poolInfo.length;
//     }

//     // Add a new lp to the pool. Can only be called by the owner.
//     // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
//     //  TODO: _dualRewarder -> this is the additional rewarder. Rewards esVWAVE tokens which will also have a pool
//     //  esVWAVE tokens get burned by Vester.sol
//     function add(
//         uint256 _allocPoint,
//         IBEP20 _asset,
//         bool _withUpdate,
//         address _dualRewarder
//     ) public onlyOwner {
//         if (_withUpdate) {
//             massUpdatePools();
//         }
//         uint256 lastRewardBlock = block.number > startBlock
//             ? block.number
//             : startBlock;
//         totalAllocPoint = totalAllocPoint.add(_allocPoint);
//         poolInfo.push(
//             PoolInfo({
//                 asset: _asset,
//                 allocPoint: _allocPoint,
//                 lastRewardBlock: lastRewardBlock,
//                 accWhalePerShare: 0,
//                 hodlMultiplierTimer: hodlMaxTimer //time required to reach 200% (max) of multiplier
//             })
//         );
//     }

//     //  TODO: add view function for frontend that tallies total ETH distributed
//     // View Function Display Total ETH Distributed
//     function totalETHDistributed() external view {}

//     // TODO: add funciton to set reward distributor
//     function setRewarddistributor(address _distributor) external onlyOwner {
//         distributor = _distributor;
//         emit NewDistributor(distributor);
//     }

//     //  TODO: add view function of each pool's current guaranteed WETH rewards
//     //  This does not represent the unclaimed WETH that
//     function poolWETH(uint256 _pid) external view {
//         PoolInfo storage pool = poolInfo[_pid]; // get pool info
//         // get total WETH entitled to pool for interval
//         pool.totalWETHPerInterval;
//         //  get current unclaimed (debt) WETH
//         pool.WETHDebt;
//         // get remaining WETH in pool
//         // interval - amount owed = not owed.
//         pool.notOwedWETH;
//     }

//     function poolDebtWETH(uint256 _pid) external view {
//         PoolInfo storage pool = poolInfo[_pid]; // get pool info
//     }

//     // TODO: distribution function only callable by distributor contract
//     function distributeWETH(uint256 _amount) external {
//         require(msg.sender == distributor, "CALLER NOT DISTRIBUTOR");
//         // get current weth balance
//         total WETH = IERC20(weth).balanceOf(address(this));
//         //  get interval WETH allocation of pool
//         uint256 length = poolInfo.length;
//         for (uint256 pid = 0; pid < length; ++pid) {
//             pool.notOwedWETH;

//             // get amount in
//             _amount;

//             // get allocation of each pool

//             pool.allocation;

//             // get pool's _amount allocation
//             _poolAmount = _amount.mul(x).div(y);
//             //  get pools unspent
//             pool.notOwedWETH;
//             // add to pools

//             // increase interval
//             interval + 1;

//             // increase total ETH distributed amount

//             emit NewFundingInterval(distributor, _amount);
//         }
//     }

//     // Update the given pool's WHALE allocation point and deposit fee. Can only be called by the owner.
//     function set(
//         uint256 _pid,
//         uint256 _allocPoint,
//         address _dualRewarder,
//         bool _withUpdate
//     ) public onlyOwner {
//         if (_withUpdate) {
//             massUpdatePools();
//         }
//         totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
//             _allocPoint
//         );
//         poolInfo[_pid].allocPoint = _allocPoint;
//         poolInfo[_pid].hodlMultiplierTimer = hodlMaxTimer;
//     }

//     // Return reward multiplier over the given _from to _to block.
//     function getMultiplier(uint256 _from, uint256 _to)
//         public
//         pure
//         returns (uint256)
//     {
//         return _to.sub(_from).mul(BONUS_MULTIPLIER);
//     }

//     //  simple function to update userpool time based on time in pool.
//     function getUserPoolTime(uint256 _pid, address _user)
//         external
//         view
//         returns (uint256)
//     {
//         PoolInfo storage pool = poolInfo[_pid]; // get pool info
//         UserInfo storage user = userInfo[_pid][_user]; // get user pool info

//         // get current time
//         currentBlockTime = block.timestamp;
//         //  get last user pool time
//         uint256 lastPoolTime = user.poolTime;
//         // simple math
//         unit256 poolDuration = now.sub(lastPoolTime);
//         // check for max. fix to 1 year.
//         if (poolDuration >= BONUS_DURATION) {
//             user.poolTime = BONUS_DURATION;
//         } else {
//             user.poolTime = poolDuration;
//         }
//         return user.poolTime;
//     }

//     // get user current multiplier for pool
//     //  TODO: Check for if PoolTime is 0
//     function getUserMultiplier(uint256 _pid, address _user)
//         external
//         view
//         returns (uint256)
//     {
//         PoolInfo storage pool = poolInfo[_pid]; // get pool info
//         UserInfo storage user = userInfo[_pid][_user]; // get user pool info

//         // we want to simply pull up UserInfo.currentBonusMultiplier
//         // should return a range from 1:100, with 1 being the start and 100 being the max
//         uint256 MaxMultiplier = 100; // end at 100%
//         // get users current time in pool.
//         uint256 userPoolTime = getUserPoolTime(_pid, _user);

//         // if greater than one year, set to one year
//         if (userPoolTime >= BONUS_DURATION) {
//             user.currentBonusMultiplier = MaxMultiplier;
//         } else {
//             // divide seconds by year
//             // bonusRatio = userPoolTime.div(BONUS_DURATION)
//             uint256 bonusRatio = userPoolTime
//                 .mul(bonusMultiplierBasisPoints)
//                 .div(BASIS_POINTS_DIVISOR)
//                 .div(BONUS_DURATION);
//             // so, if in for 30 days -> 2,592,000 seconds / 1 year -> 31536000 = 0.082191780821918 * 100 = 8.21917808219178% bonus
//             user.currentBonusMultiplier = bonusRatio;
//             // return timeDiff.mul(supply).mul(bonusMultiplierBasisPoints).div(BASIS_POINTS_DIVISOR).div(BONUS_DURATION);
//         }

//         return user.currentBonusMultiplier;
//     }

//     // View function to see pending WHALEs on frontend.
//     function pendingWETH(uint256 _pid, address _user)
//         external
//         view
//         returns (uint256)
//     {
//         PoolInfo storage pool = poolInfo[_pid];
//         UserInfo storage user = userInfo[_pid][_user];
//         // get total WETH accumulated per share of pool
//         uint256 accWETHPerShare = pool.accWETHPerShare;
//         //  get total asset balance in pool
//         uint256 tokenBalance = pool.asset.balanceOf(address(this));

//         if (block.number > pool.lastRewardBlock && tokenBalance != 0) {
//             //  to - from * 1
//             // block 100 - block 98 * 1 = 2
//             uint256 multiplier = getUserMultiplier(_pid, _user);
//             // multiplier * reward per block * pool's allocation % total allocation

//             // this wont work unless we determine wethPerBlock as fixed each week.
//             uint256 wethRewards = multiplier
//                 .mul(whalePerBlock)
//                 .mul(pool.allocPoint)
//                 .div(totalAllocPoint);
//             accWhalePerShare = accWhalePerShare.add(
//                 whaleReward.mul(1e12).div(lpSupply)
//             );
//         }

//         uint256 pending = user.amount.mul(accWhalePerShare).div(1e12).sub(
//             user.rewardDebt
//         );
//         return pending.add(user.rewardLockedUp);
//     }

//     // Update reward variables for all pools. Be careful of gas spending!
//     function massUpdatePools() public {
//         uint256 length = poolInfo.length;
//         for (uint256 pid = 0; pid < length; ++pid) {
//             updatePool(pid);
//         }
//     }

//     // Update reward variables of the given pool to be up-to-date.
//     function updatePool(uint256 _pid) public {
//         PoolInfo storage pool = poolInfo[_pid];
//         if (block.number <= pool.lastRewardBlock) {
//             return;
//         }
//         uint256 lpSupply = pool.lpToken.balanceOf(address(this));
//         if (lpSupply == 0 || pool.allocPoint == 0) {
//             pool.lastRewardBlock = block.number;
//             return;
//         }
//         uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
//         uint256 whaleReward = multiplier
//             .mul(whalePerBlock)
//             .mul(pool.allocPoint)
//             .div(totalAllocPoint);
//         whale.mint(address(this), whaleReward.mul(2));
//         pool.accWhalePerShare = pool.accWhalePerShare.add(
//             whaleReward.mul(1e12).div(lpSupply)
//         );
//         pool.lastRewardBlock = block.number;
//     }

//     // Deposit LP tokens to MasterChef for WHALE allocation.
//     function deposit(
//         uint256 _pid,
//         uint256 _amount,
//         address _referrer,
//         bool toHarvest
//     ) public nonReentrant {
//         PoolInfo storage pool = poolInfo[_pid];
//         UserInfo storage user = userInfo[_pid][msg.sender];
//         updatePool(_pid);
//         if (_amount > 0 && _referrer != address(0) && _referrer != msg.sender) {
//             recordReferral(msg.sender, _referrer);
//         }
//         payOrLockupPendingWhale(_pid, toHarvest);
//         if (_amount > 0) {
//             //account for transfer tax
//             uint256 previousAmount = pool.lpToken.balanceOf(address(this));
//             pool.lpToken.safeTransferFrom(
//                 address(msg.sender),
//                 address(this),
//                 _amount
//             );
//             uint256 afterAmount = pool.lpToken.balanceOf(address(this));
//             _amount = afterAmount.sub(previousAmount);
//             if (pool.depositFeeBP > 0) {
//                 uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
//                 pool.lpToken.safeTransfer(feeAddress, depositFee);
//                 user.amount = user.amount.add(_amount).sub(depositFee);
//             } else {
//                 user.amount = user.amount.add(_amount);
//             }
//         }
//         user.rewardDebt = user.amount.mul(pool.accWhalePerShare).div(1e12);
//         updateEmissionRate();
//         emit Deposit(msg.sender, _pid, _amount);
//     }

//     //  TODO: Add subtraction of bonus multiplier
//     //  if bonus is 100% and they remove 50% of balance, bonus should be 50%

//     // Withdraw LP tokens from MasterChef.
//     function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
//         PoolInfo storage pool = poolInfo[_pid];
//         UserInfo storage user = userInfo[_pid][msg.sender];
//         require(user.amount >= _amount, "withdraw: not good");
//         updatePool(_pid);
//         uint256 pending = user.amount.mul(pool.accCakePerShare).div(1e12).sub(
//             user.rewardDebt
//         );
//         if (pending > 0) {
//             safeCakeTransfer(msg.sender, pending);
//         }
//         if (_amount > 0) {
//             user.amount = user.amount.sub(_amount);
//             pool.lpToken.safeTransfer(address(msg.sender), _amount);
//         }
//         user.rewardDebt = user.amount.mul(pool.accWhalePerShare).div(1e12);
//         updateEmissionRate();
//         emit Withdraw(msg.sender, _pid, _amount);
//     }

//     //  TODO: 100% is removed, so 100% of multiplier should be removed
//     //  TODO: set pool entrance to 0
//     // Withdraw without caring about rewards. EMERGENCY ONLY.
//     function emergencyWithdraw(uint256 _pid) public nonReentrant {
//         PoolInfo storage pool = poolInfo[_pid];
//         UserInfo storage user = userInfo[_pid][msg.sender];
//         uint256 amount = user.amount;
//         user.amount = 0;
//         user.rewardDebt = 0;
//         user.rewardLockedUp = 0;
//         user.nextHarvestUntil = 0;
//         pool.lpToken.safeTransfer(address(msg.sender), amount);
//         emit EmergencyWithdraw(msg.sender, _pid, amount);
//     }

//     // Safe whale transfer function, just in case if rounding error causes pool to not have enough WHALEs.
//     function safeETH(address _to, uint256 _amount) internal {
//         uint256 wethBal = weth.balanceOf(address(this));
//         if (_amount > wethBal) {
//             weth.transfer(_to, whaleBal);
//         } else {
//             weth.transfer(_to, _amount);
//         }
//     }

//     // Update dev address by the previous dev.
//     function setDevAddress(address _devAddress) public {
//         require(msg.sender == devAddress, "setDevAddress: FORBIDDEN");
//         require(_devAddress != address(0), "setDevAddress: ZERO");
//         devAddress = _devAddress;
//     }

//     // Update startBlock by the owner (added this to ensure that dev can delay startBlock due to the congestion in BSC). Only used if required.
//     function setstartBlock(uint256 _startBlock) public onlyOwner {
//         startBlock = _startBlock;
//     }

//     //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
//     function updateEmissionRate() public {
//         // require(block.number > startBlock, "updateEmissionRate: Can only be called after mining starts");
//         // require(whalePerBlock > MINIMUM_EMISSION_RATE, "updateEmissionRate: Emission rate has reached the minimum threshold");
//         if (block.number <= startBlock) {
//             return;
//         }
//         if (whalePerBlock <= MINIMUM_EMISSION_RATE) {
//             return;
//         }
//         uint256 currentIndex = block.number.sub(startBlock).div(
//             emissionReductionPeriodBlocks
//         );
//         if (currentIndex <= lastReductionPeriodIndex) {
//             return;
//         }

//         uint256 newEmissionRate = whalePerBlock;
//         for (
//             uint256 index = lastReductionPeriodIndex;
//             index < currentIndex;
//             ++index
//         ) {
//             newEmissionRate = newEmissionRate
//                 .mul(1e4 - EMISSION_REDUCTION_RATE_PER_PERIOD)
//                 .div(1e4);
//         }

//         newEmissionRate = newEmissionRate < MINIMUM_EMISSION_RATE
//             ? MINIMUM_EMISSION_RATE
//             : newEmissionRate;
//         if (newEmissionRate >= whalePerBlock) {
//             return;
//         }
//         massUpdatePools();
//         lastReductionPeriodIndex = currentIndex;
//         whalePerBlock = newEmissionRate;
//         emissionReductionPeriodBlocks = emissionReductionPeriodBlocks
//             .mul(EMISSION_EXTENDED_PERIOD_EACH_EPOCH)
//             .div(1e3);
//     }
// }
