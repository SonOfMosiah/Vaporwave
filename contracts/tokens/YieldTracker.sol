//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IDistributor.sol";
import "./interfaces/IYieldTracker.sol";
import "./interfaces/IYieldToken.sol";

/// Sender does not have permission to call this function
error Forbidden();

// code adapated from https://github.com/trusttoken/smart-contracts/blob/master/contracts/truefi/TrueFarm.sol
/// @title Vaporwave Yield Tracker
contract YieldTracker is IYieldTracker, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e30;

    address public yieldToken;
    address public distributor;

    uint256 public cumulativeRewardPerToken;
    mapping(address => uint256) public claimableReward;
    mapping(address => uint256) public previousCumulatedRewardPerToken;

    /// @notice Emitted when rewards are claimed
    /// @param receiver The address claiming the rewards
    /// @param amount The amount of tokens claimed
    event Claim(address receiver, uint256 amount);

    constructor(address _yieldToken) {
        _transferOwnership(msg.sender);
        yieldToken = _yieldToken;
    }

    /// @notice Set the distributor to `_distributor`
    /// @param _distributor The new distributor
    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
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
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    /// @notice Claim rewards
    /// @dev Emits a `Claim` event
    /// @param _account The account to claim rewards from
    /// @param _receiver The account to receive the rewards
    function claim(address _account, address _receiver)
        external
        override
        returns (uint256)
    {
        if (msg.sender != yieldToken) {
            revert Forbidden();
        }
        updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        address rewardToken = IDistributor(distributor).getRewardToken(
            address(this)
        );
        IERC20(rewardToken).safeTransfer(_receiver, tokenAmount);
        emit Claim(_account, tokenAmount);

        return tokenAmount;
    }

    /// @notice Get the tokens per interval
    /// @return The tokens per interval
    function getTokensPerInterval() external view override returns (uint256) {
        return IDistributor(distributor).tokensPerInterval(address(this));
    }

    /// @notice Get the claimable amount for `_account`
    /// @param _account The account to query for the claimable amount
    /// @return The claimable amount for `_account`
    function claimable(address _account)
        external
        view
        override
        returns (uint256)
    {
        uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
        if (stakedBalance == 0) {
            return claimableReward[_account];
        }
        uint256 pendingRewards = IDistributor(distributor)
            .getDistributionAmount(address(this)) * PRECISION;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken +
            (pendingRewards / totalStaked);
        return
            claimableReward[_account] +
            ((stakedBalance *
                (nextCumulativeRewardPerToken -
                    (previousCumulatedRewardPerToken[_account]))) /
                (PRECISION));
    }

    /// @notice Update the rewards for `_account`
    /// @param _account The account to update the rewards for
    function updateRewards(address _account) public override nonReentrant {
        uint256 blockReward;

        if (distributor != address(0)) {
            blockReward = IDistributor(distributor).distribute();
        }

        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        // only update cumulativeRewardPerToken when there are stakers, i.e. when totalStaked > 0
        // if blockReward == 0, then there will be no change to cumulativeRewardPerToken
        if (totalStaked > 0 && blockReward > 0) {
            _cumulativeRewardPerToken =
                _cumulativeRewardPerToken +
                ((blockReward * (PRECISION)) / (totalStaked));
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (_account != address(0)) {
            uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(
                _account
            );
            uint256 _previousCumulatedReward = previousCumulatedRewardPerToken[
                _account
            ];
            uint256 _claimableReward = claimableReward[_account] +
                ((stakedBalance *
                    (_cumulativeRewardPerToken - (_previousCumulatedReward))) /
                    (PRECISION));

            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[
                _account
            ] = _cumulativeRewardPerToken;
        }
    }
}
