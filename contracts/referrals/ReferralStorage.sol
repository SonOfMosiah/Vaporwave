// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../peripherals/interfaces/ITimelock.sol";

import "./interfaces/IReferralStorage.sol";

/// User does not have permission to call function
error Forbidden();
/// Code can't be 0
error InvalidCode();

/// @title Vaporwave Referral Storage
contract ReferralStorage is Ownable, IReferralStorage {
    struct Tier {
        uint256 totalRebate; // e.g. 2400 for 24%
        uint256 discountShare; // 5000 for 50%/50%, 7000 for 30% rebates/70% discount
    }

    uint256 public constant BASIS_POINTS = 10000;

    /// mapping of referrer to discount shares
    mapping(address => uint256) public referrerDiscountShares; // to override default value in tier
    /// mapping of referrer to tier
    mapping(address => uint256) public referrerTiers; // link between user <> tier
    /// mapping of index to tier
    mapping(uint256 => Tier) public tiers;

    /// mapping of handlers
    mapping(address => bool) public isHandler;
    /// mapping of codes to owners
    mapping(bytes32 => address) public override codeOwners;
    /// mapping of accounts to codes
    mapping(address => bytes32) public traderReferralCodes;

    event SetHandler(address handler, bool isActive);
    event SetTraderReferralCode(address account, bytes32 code);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare);
    event SetReferrerTier(address referrer, uint256 tierId);
    event SetReferrerDiscountShare(address referrer, uint256 discountShare);
    event RegisterCode(address account, bytes32 code);
    event SetCodeOwner(address account, address newAccount, bytes32 code);
    event GovSetCodeOwner(bytes32 code, address newAccount);

    modifier onlyHandler() {
        if (!isHandler[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    /// @notice Set a handler for the contract
    /// @param _handler The address of the handler
    /// @param _isActive Whether to enable or disable the account as a handler
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    /// @notice Set tier
    /// @param _tierId The ID of the tier
    /// @param _totalRebate The total rebate
    /// @param _discountShare The discount share
    function setTier(
        uint256 _tierId,
        uint256 _totalRebate,
        uint256 _discountShare
    ) external override onlyOwner {
        require(
            _totalRebate <= BASIS_POINTS,
            "ReferralStorage: invalid totalRebate"
        );
        require(
            _discountShare <= BASIS_POINTS,
            "ReferralStorage: invalid discountShare"
        );

        Tier memory tier = tiers[_tierId];
        tier.totalRebate = _totalRebate;
        tier.discountShare = _discountShare;
        tiers[_tierId] = tier;
        emit SetTier(_tierId, _totalRebate, _discountShare);
    }

    /// @notice Set referrer tier
    /// @param _referrer The address of the referrer
    /// @param _tierId The ID of the tier
    function setReferrerTier(address _referrer, uint256 _tierId)
        external
        override
        onlyOwner
    {
        referrerTiers[_referrer] = _tierId;
        emit SetReferrerTier(_referrer, _tierId);
    }

    /// @notice Set referrer discount share
    /// @param _discountShare The discount share
    function setReferrerDiscountShare(uint256 _discountShare) external {
        require(
            _discountShare <= BASIS_POINTS,
            "ReferralStorage: invalid discountShare"
        );

        referrerDiscountShares[msg.sender] = _discountShare;
        emit SetReferrerDiscountShare(msg.sender, _discountShare);
    }

    /// @notice Set a trader referral code
    /// @param _account The address of the trader
    /// @param _code The referral code
    function setTraderReferralCode(address _account, bytes32 _code)
        external
        override
        onlyHandler
    {
        _setTraderReferralCode(_account, _code);
    }

    /// @notice Set own trader referral code
    /// @param _code The referral code
    function setTraderReferralCodeByUser(bytes32 _code) external {
        _setTraderReferralCode(msg.sender, _code);
    }

    /// @notice Register a referral code
    /// @param _code The referral code
    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");
        require(
            codeOwners[_code] == address(0),
            "ReferralStorage: code already exists"
        );

        codeOwners[_code] = msg.sender;
        emit RegisterCode(msg.sender, _code);
    }

    /// @notice Set a new owner for a referral code
    /// @param _code The referral code
    /// @param _newAccount The new owner of the referral code
    function setCodeOwner(bytes32 _code, address _newAccount) external {
        if (_code == bytes32(0)) {
            revert InvalidCode();
        }

        address account = codeOwners[_code];
        require(msg.sender == account, "ReferralStorage: forbidden");

        codeOwners[_code] = _newAccount;
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }

    /// @notice Set a new owner for a referral code
    /// @param _code The referral code
    /// @param _newAccount The new owner of the referral code
    function govSetCodeOwner(bytes32 _code, address _newAccount)
        external
        override
        onlyOwner
    {
        if (_code == bytes32(0)) {
            revert InvalidCode();
        }

        codeOwners[_code] = _newAccount;
        emit GovSetCodeOwner(_code, _newAccount);
    }

    /// @notice Get trader's referral info
    /// @param _account The address of the trader
    function getTraderReferralInfo(address _account)
        external
        view
        override
        returns (bytes32, address)
    {
        bytes32 code = traderReferralCodes[_account];
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    function _setTraderReferralCode(address _account, bytes32 _code) private {
        traderReferralCodes[_account] = _code;
        emit SetTraderReferralCode(_account, _code);
    }
}
