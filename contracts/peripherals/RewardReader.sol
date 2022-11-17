// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../staking/interfaces/IRewardTracker.sol";

contract RewardReader {
    function getDepositBalances(
        address _account,
        address[] memory _depositTokens,
        address[] memory _rewardTrackers
    ) public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](_rewardTrackers.length);
        for (uint256 i = 0; i < _rewardTrackers.length; i++) {
            IRewardTracker rewardTracker = IRewardTracker(_rewardTrackers[i]);
            amounts[i] = rewardTracker.depositBalances(
                _account,
                _depositTokens[i]
            );
        }
        return amounts;
    }

    function getStakingInfo(address _account, address[] memory _rewardTrackers)
        public
        view
        returns (uint256[] memory)
    {
        uint256 propsLength = 5;
        uint256[] memory amounts = new uint256[](
            _rewardTrackers.length * propsLength
        );
        for (uint256 i = 0; i < _rewardTrackers.length; i++) {
            IRewardTracker rewardTracker = IRewardTracker(_rewardTrackers[i]);
            amounts[i * propsLength] = rewardTracker.claimable(_account);
            amounts[i * propsLength + 1] = rewardTracker.tokensPerInterval();
            amounts[i * propsLength + 2] = rewardTracker.averageStakedAmounts(
                _account
            );
            amounts[i * propsLength + 3] = rewardTracker.cumulativeRewards(
                _account
            );
            amounts[i * propsLength + 4] = IERC20(_rewardTrackers[i])
                .totalSupply();
        }
        return amounts;
    }
}
