// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IPriceFeed.sol";

/// Sender is not a valid admin
error OnlyAdmin();

/// @title Vaporwave Price Feed
contract PriceFeed is IPriceFeed, Ownable {
    int256 public answer;
    uint80 public roundId;
    string public override description = "PriceFeed";
    address public override aggregator;

    uint256 public decimals;

    mapping(uint80 => int256) public answers;
    mapping(address => bool) public isAdmin;

    constructor() {
        isAdmin[msg.sender] = true;
    }

    /// @notice Set `_account` as an admin true/false: _isAdmin
    /// @param _account The account to set as admin
    /// @param _isAdmin True/false if the account is an admin
    function setAdmin(address _account, bool _isAdmin) public onlyOwner {
        isAdmin[_account] = _isAdmin;
    }

    /// @notice Set the latest answer to `_answer`
    /// @param _answer The new answer
    function setLatestAnswer(int256 _answer) public {
        if (!isAdmin[msg.sender]) {
            revert OnlyAdmin();
        }
        roundId = roundId + 1;
        answer = _answer;
        answers[roundId] = _answer;
    }

    /// @notice Get the latest answer
    /// @return The latest answer
    function latestAnswer() public view override returns (int256) {
        return answer;
    }

    /// @notice Get the latest round
    /// @return The latest round
    function latestRound() public view override returns (uint80) {
        return roundId;
    }

    /// @notice Get the round datd for id `_roundId`
    // returns roundId, answer, startedAt, updatedAt, answeredInRound
    function getRoundData(uint80 _roundId)
        public
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        return (_roundId, answers[_roundId], 0, 0, 0);
    }
}
