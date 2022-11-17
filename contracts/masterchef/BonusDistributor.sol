// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// import "../staking/interfaces/IRewardDistributor.sol";
// import "../staking/interfaces/IRewardTracker.sol";

// error InvalidLastDistributionTime();

// contract BonusDistributor is IRewardDistributor, ReentrancyGuard, Ownable {
//     using SafeERC20 for IERC20;

//     uint256 public constant BASIS_POINTS_DIVISOR = 10000;
//     uint256 public constant BONUS_DURATION = 365 days;

//     uint256 public bonusMultiplierBasisPoints;

//     address public override rewardToken;
//     uint256 public lastDistributionTime;
//     address public rewardTracker;

//     address public admin;

//     event Distribute(uint256 amount);
//     event BonusMultiplierChange(uint256 amount);

//     modifier onlyAdmin() {
//         require(msg.sender == admin, "BonusDistributor: forbidden");
//         _;
//     }

//     constructor(address _rewardToken, address _rewardTracker) {
//         rewardToken = _rewardToken;
//         rewardTracker = _rewardTracker;
//         admin = msg.sender;
//     }

//     function setAdmin(address _admin) external onlyOwner {
//         admin = _admin;
//     }

//     /// @notice Withdraw tokens from this contract
//     /// @dev to help users who accidentally send their tokens to this contract
//     /// @param _token The token to withdraw from this contract
//     /// @param _account The account to send the tokens to
//     /// @param _amount The amount of tokens to withdraw
//     function withdrawToken(
//         address _token,
//         address _account,
//         uint256 _amount
//     ) external onlyOwner {
//         IERC20(_token).safeTransfer(_account, _amount);
//     }

//     /// @notice Update the last distribution time
//     /// @dev This is called by the reward tracker when it distributes rewards
//     function updateLastDistributionTime() external onlyAdmin {
//         /*solhint-disable-next-line not-rely-on-time*/
//         lastDistributionTime = block.timestamp;
//     }

//     function setBonusMultiplier(uint256 _bonusMultiplierBasisPoints)
//         external
//         onlyAdmin
//     {
//         if (lastDistributionTime == 0) {
//             revert InvalidLastDistributionTime();
//         }

//         IRewardTracker(rewardTracker).updateRewards();
//         bonusMultiplierBasisPoints = _bonusMultiplierBasisPoints;
//         emit BonusMultiplierChange(_bonusMultiplierBasisPoints);
//     }

//     //   this is pretty simple.
//     // essentially a 'tokens per block' function
//     // always calculates the amount of tokens current available ()
//     function tokensPerInterval() public view override returns (uint256) {
//         //  get total supply of rewardTracker token. NOT the total supply of available rewards.
//         // supply is increased/decreased from deposit/withdraw
//         // so supply here = total pool balance
//         //
//         uint256 supply = IERC20(rewardTracker).totalSupply();
//         // total supply * bonusMultiplierBasisPoints / BASIS_POINTS_DIVISOR / BONUS_DURATION
//         // total supply * (10,000 % 10,000) % 31536000 = total supply * 1 % 31536000
//         // 100 WETH % 31536000

//         return
//             supply
//                 .mul(bonusMultiplierBasisPoints)
//                 .div(BASIS_POINTS_DIVISOR)
//                 .div(BONUS_DURATION);
//     }

//     function pendingRewards() public view override returns (uint256) {
//         if (block.timestamp == lastDistributionTime) {
//             return 0;
//         }

//         uint256 supply = IERC20(rewardTracker).totalSupply();
//         uint256 timeDiff = block.timestamp.sub(lastDistributionTime);

//         return
//             timeDiff
//                 .mul(supply)
//                 .mul(bonusMultiplierBasisPoints)
//                 .div(BASIS_POINTS_DIVISOR)
//                 .div(BONUS_DURATION);
//     }

//     function distribute() external override returns (uint256) {
//         require(
//             msg.sender == rewardTracker,
//             "BonusDistributor: invalid msg.sender"
//         );
//         uint256 amount = pendingRewards();
//         if (amount == 0) {
//             return 0;
//         }

//         lastDistributionTime = block.timestamp;

//         uint256 balance = IERC20(rewardToken).balanceOf(address(this));
//         if (amount > balance) {
//             amount = balance;
//         }

//         IERC20(rewardToken).safeTransfer(msg.sender, amount);

//         emit Distribute(amount);
//         return amount;
//     }
// }
