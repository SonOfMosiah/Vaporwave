// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/ITimelockTarget.sol";
import "./interfaces/ITimelock.sol";
import "./interfaces/IHandlerTarget.sol";
import "../access/interfaces/IAdmin.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVaultUtils.sol";
import "../core/interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IFastPriceFeed.sol";
import "../core/interfaces/IRouter.sol";
import "../referrals/interfaces/IReferralStorage.sol";
import "../tokens/interfaces/IYieldToken.sol";
import "../tokens/interfaces/IBaseToken.sol";
import "../tokens/interfaces/IMintable.sol";

/// User is not authorized to call this function
error TimelockForbidden();
/// The target cannot be this contract
error InvalidTarget();
/// The buffer is greater than the max allowed
error InvalidBuffer();
/// Max leverage must be greater than `MAX_LEVERAGE_VALIDATION`
error InvalidMaxLeverage();
/// Max gas price must be greater than `_`
error InvalidMaxGasPrice();
/// The funding rate factor is greater than the max allowed
error InvalidFundingRateFactor();
/// The stable funding rate factor is greater than the max allowed
error InvalidStableFundingRateFactor();
/// Min Profit BPS must be greater than 500
error InvalidMinProfitBps();
/// The token is not on the allowlist
error TokenNotAllowlisted();
/// Excluded tokens must have transfers enabled
error InvalidInPrivateTransferMode();
/// Array parameters do not have the same length
error InvalidArrayLengths();
/// The action's locked time has not yet passed
error TimeNotPassed();
/// The action has not been created
error InvalidAction();
/// Attempting to mint more than the max supply
error MaxTokenSupplyExceeded();

/// @title Timelock
contract Timelock is ITimelock {
    /// The max funding rate factor is 200 (0.02%)
    uint16 public constant MAX_FUNDING_RATE_FACTOR = 200;
    /// The maximum leverage must be greater than 500000 (50x)
    uint32 public constant MAX_LEVERAGE_VALIDATION = 5e5;
    /// The maximum buffer is 5 days (432000 seconds)
    uint32 public constant MAX_BUFFER = 5 days;
    /// Helper to avoid truncation errors in price calculations
    uint128 public constant PRICE_PRECISION = 1e30;
    uint64 private constant _MAX_GAS_PRICE_VALIDATION = 5e9;

    /// The buffer amount in seconds
    uint256 public buffer;
    /// The admin of the contract
    address public admin;

    /// The token manager address
    address public tokenManager;
    /// The reward manager address
    address public rewardManager;
    /// The address to receive newly minted tokens
    address public mintReceiver;
    /// The max token supply
    uint256 public maxTokenSupply;

    /// The margin fee basis points
    uint256 public marginFeeBasisPoints;
    /// The max margin fee basis points
    uint256 public maxMarginFeeBasisPoints;
    /// If this contract should be able to enable/disable leverage
    bool public shouldToggleIsLeverageEnabled;

    /// Mapping of pending actions
    mapping(bytes32 => uint256) public pendingActions;
    /// Mapping of excluded tokens
    mapping(address => bool) public excludedTokens;

    /// Mapping of valid handlers
    mapping(address => bool) public isHandler;

    event SignalPendingAction(bytes32 action);
    event SignalApprove(
        address token,
        address spender,
        uint256 amount,
        bytes32 action
    );
    event SignalWithdrawToken(
        address target,
        address token,
        address receiver,
        uint256 amount,
        bytes32 action
    );
    event SignalMint(
        address token,
        address receiver,
        uint256 amount,
        bytes32 action
    );
    event SignalSetOwner(address target, address owner, bytes32 action);
    event SignalSetHandler(
        address target,
        address handler,
        bool isActive,
        bytes32 action
    );
    event SignalSetPriceFeed(address vault, address priceFeed, bytes32 action);
    event SignalAddPlugin(address router, address plugin, bytes32 action);
    event SignalSetPriceFeedWatcher(
        address fastPriceFeed,
        address account,
        bool isActive
    );
    event SignalVaultSetTokenConfig(
        address vault,
        address token,
        uint256 tokenDecimals,
        uint256 tokenWeight,
        uint256 minProfitBps,
        bool isStable,
        bool isShortable
    );
    event SignalPriceFeedSetTokenConfig(
        address vaultPriceFeed,
        address token,
        address priceFeed,
        uint256 priceDecimals,
        bool isStrictStable
    );
    event ClearAction(bytes32 action);

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert TimelockForbidden();
        }
        _;
    }

    modifier onlyAdminOrHandler() {
        if (msg.sender != admin && !isHandler[msg.sender]) {
            revert TimelockForbidden();
        }
        _;
    }

    modifier onlyTokenManager() {
        if (msg.sender != tokenManager) {
            revert TimelockForbidden();
        }
        _;
    }

    modifier onlyRewardManager() {
        if (msg.sender != rewardManager) {
            revert TimelockForbidden();
        }
        _;
    }

    constructor(
        address _admin,
        uint256 _buffer,
        address _rewardManager,
        address _tokenManager,
        address _mintReceiver,
        uint256 _maxTokenSupply,
        uint256 _marginFeeBasisPoints,
        uint256 _maxMarginFeeBasisPoints
    ) {
        if (_buffer > MAX_BUFFER) {
            revert InvalidBuffer();
        }
        admin = _admin;
        buffer = _buffer;
        rewardManager = _rewardManager;
        tokenManager = _tokenManager;
        mintReceiver = _mintReceiver;
        maxTokenSupply = _maxTokenSupply;

        marginFeeBasisPoints = _marginFeeBasisPoints;
        maxMarginFeeBasisPoints = _maxMarginFeeBasisPoints;
    }

    /// @notice Set the admin of this contract to `_admin`
    /// @param _admin The new admin of this contract
    function setAdmin(address _admin) external override onlyTokenManager {
        admin = _admin;
    }

    /// @notice Set the admin of `_target` to `_admin`
    /// @param _target The external contract
    /// @param _admin The new admin of `_target`
    function setExternalAdmin(address _target, address _admin)
        external
        onlyAdmin
    {
        if (_target == address(this)) {
            revert InvalidTarget();
        }
        IAdmin(_target).setAdmin(_admin);
    }

    /// @notice Set `_handler` as a contract handler true/false: `_isActive`
    /// @param _handler The contract handler to set
    /// @param _isActive True to activate, false to deactivate
    function setContractHandler(address _handler, bool _isActive)
        external
        onlyAdmin
    {
        isHandler[_handler] = _isActive;
    }

    /// @notice Set the buffer to `_buffer`
    /// @param _buffer The new buffer
    function setBuffer(uint256 _buffer) external onlyAdmin {
        if (_buffer > MAX_BUFFER || _buffer <= buffer) {
            revert InvalidBuffer();
        }
        buffer = _buffer;
    }

    /// @notice Set shouldToggleIsLeverageEnabled to `_shouldToggleIsLeverageEnabled`
    /// @dev Variable must be set to true before this contract can enable or disable leverage on the vault
    /// @param _shouldToggleIsLeverageEnabled True to enable, false to disable
    function setShouldToggleIsLeverageEnabled(
        bool _shouldToggleIsLeverageEnabled
    ) external onlyAdminOrHandler {
        shouldToggleIsLeverageEnabled = _shouldToggleIsLeverageEnabled;
    }

    /// @notice Set the margin fee basis points parameters
    /// @param _marginFeeBasisPoints The margin fee basis points
    /// @param _maxMarginFeeBasisPoints The max margin fee basis points
    function setMarginFeeBasisPoints(
        uint256 _marginFeeBasisPoints,
        uint256 _maxMarginFeeBasisPoints
    ) external onlyAdminOrHandler {
        marginFeeBasisPoints = _marginFeeBasisPoints;
        maxMarginFeeBasisPoints = _maxMarginFeeBasisPoints;
    }

    function addExcludedToken(address _token) external onlyAdmin {
        excludedTokens[_token] = true;
    }

    /// @notice Cancel an action
    /// @param _action The action to cancel
    function cancelAction(bytes32 _action) external onlyAdmin {
        _clearAction(_action);
    }

    /// @notice Mint `_amount` of `_token` to `mintReceiver`
    /// @dev This contract must have minter rights or ability to set minter
    /// @param _token The token to mint
    /// @param _amount The amount to mint
    function mint(address _token, uint256 _amount) external onlyAdmin {
        _mint(_token, mintReceiver, _amount);
    }

    /// @notice Set the max leverage on `_vault` to `_maxLeverage`
    /// @param _vault The vault address
    /// @param _maxLeverage The new max leverage
    function setMaxLeverage(address _vault, uint256 _maxLeverage)
        external
        onlyAdmin
    {
        if (_maxLeverage <= MAX_LEVERAGE_VALIDATION) {
            revert InvalidMaxLeverage();
        }
        IVault(_vault).setMaxLeverage(_maxLeverage);
    }

    /// @notice Set the funding rate parameters on `_vault`
    /// @param _vault The vault address
    /// @param _fundingInterval The funding interval
    /// @param _fundingRateFactor The funding rate factor for non-stablecoins
    /// @param _stableFundingRateFactor The funding rate factor for stablecoins
    function setFundingRate(
        address _vault,
        uint256 _fundingInterval,
        uint256 _fundingRateFactor,
        uint256 _stableFundingRateFactor
    ) external onlyAdminOrHandler {
        if (_fundingRateFactor > MAX_FUNDING_RATE_FACTOR) {
            revert InvalidFundingRateFactor();
        }
        if (_stableFundingRateFactor > MAX_FUNDING_RATE_FACTOR) {
            revert InvalidStableFundingRateFactor();
        }
        IVault(_vault).setFundingRate(
            _fundingInterval,
            _fundingRateFactor,
            _stableFundingRateFactor
        );
    }

    // TODO finish param descriptions
    /// @notice Set the swap fees
    /// @param _vault The vault address
    // @param _taxBasisPoints
    // @param _stableTaxBasisPoints
    // @param _mintBurnFeeBasisPoints
    // @param _swapFeeBasisPoints
    // @param _stableSwapFeeBasisPoints
    function setSwapFees(
        address _vault,
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints
    ) external onlyAdminOrHandler {
        IVault vault = IVault(_vault);

        vault.setFees(
            _taxBasisPoints,
            _stableTaxBasisPoints,
            _mintBurnFeeBasisPoints,
            _swapFeeBasisPoints,
            _stableSwapFeeBasisPoints,
            maxMarginFeeBasisPoints,
            vault.liquidationFeeUsd(),
            vault.minProfitTime(),
            vault.hasDynamicFees()
        );
    }

    /// @notice Set the vault fees
    /// @dev Calls the vault's setFees function
    /// @dev assign _marginFeeBasisPoints to this.marginFeeBasisPoints
    /// @dev because enableLeverage would update Vault.marginFeeBasisPoints to this.marginFeeBasisPoints
    /// @dev and disableLeverage would reset the Vault.marginFeeBasisPoints to this.maxMarginFeeBasisPoints
    // @param _vault The vault address
    // @param _taxBasispoints
    // @param _stableTaxBasisPoints
    // @param _mintBurnFeeBasisPoints
    // @param _swapFeeBasisPoints
    // @param _stableSwapFeeFeeBasisPoints
    // @param _marginFeeBasisPoints
    // @param _liquidationFeeUsd
    // @param _minProfitTime
    // @param _hasDynamicFees True to enable dynamic fees, false otherwise
    function setFees(
        address _vault,
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external onlyAdminOrHandler {
        marginFeeBasisPoints = _marginFeeBasisPoints;

        IVault(_vault).setFees(
            _taxBasisPoints,
            _stableTaxBasisPoints,
            _mintBurnFeeBasisPoints,
            _swapFeeBasisPoints,
            _stableSwapFeeBasisPoints,
            maxMarginFeeBasisPoints,
            _liquidationFeeUsd,
            _minProfitTime,
            _hasDynamicFees
        );
    }

    /// @notice Enable leverage on `_vault`
    /// @dev `shouldToggleIsLeveragedEnabled` must be true
    /// @param _vault The vault address
    function enableLeverage(address _vault)
        external
        override
        onlyAdminOrHandler
    {
        IVault vault = IVault(_vault);

        if (shouldToggleIsLeverageEnabled) {
            vault.setIsLeverageEnabled(true);
        }

        vault.setFees(
            vault.taxBasisPoints(),
            vault.stableTaxBasisPoints(),
            vault.mintBurnFeeBasisPoints(),
            vault.swapFeeBasisPoints(),
            vault.stableSwapFeeBasisPoints(),
            marginFeeBasisPoints,
            vault.liquidationFeeUsd(),
            vault.minProfitTime(),
            vault.hasDynamicFees()
        );
    }

    /// @notice Disable leverage on `_vault`
    /// @dev `shouldToggleIsLeveragedEnabled` must be true
    /// @param _vault The vault address
    function disableLeverage(address _vault)
        external
        override
        onlyAdminOrHandler
    {
        IVault vault = IVault(_vault);

        if (shouldToggleIsLeverageEnabled) {
            vault.setIsLeverageEnabled(false);
        }

        vault.setFees(
            vault.taxBasisPoints(),
            vault.stableTaxBasisPoints(),
            vault.mintBurnFeeBasisPoints(),
            vault.swapFeeBasisPoints(),
            vault.stableSwapFeeBasisPoints(),
            maxMarginFeeBasisPoints, // marginFeeBasisPoints
            vault.liquidationFeeUsd(),
            vault.minProfitTime(),
            vault.hasDynamicFees()
        );
    }

    /// @notice Set the isLeverageEnabled flag on `_vault` to `_isLeverageEnabled`
    /// @param _vault The vault address
    /// @param _isLeverageEnabled True to enable leverage, false otherwise
    function setIsLeverageEnabled(address _vault, bool _isLeverageEnabled)
        external
        override
        onlyAdminOrHandler
    {
        IVault(_vault).setIsLeverageEnabled(_isLeverageEnabled);
    }

    /// @notice Set Token Configurations
    /// @param _vault The vault address
    /// @param _token The token address
    /// @param _tokenWeight The token weight
    /// @param _minProfitBps The minimum profit in basis points
    /// @param _maxUsdAmount The maximum usd amount
    /// @param _bufferAmount The buffer amount
    function setTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        uint256 _maxUsdAmount,
        uint256 _bufferAmount
    ) external onlyAdminOrHandler {
        if (_minProfitBps > 500) {
            revert InvalidMinProfitBps();
        }

        IVault vault = IVault(_vault);
        if (!vault.allowlistedTokens(_token)) {
            revert TokenNotAllowlisted();
        }

        uint256 tokenDecimals = vault.tokenDecimals(_token);
        bool isStable = vault.stableTokens(_token);
        bool isShortable = vault.shortableTokens(_token);

        IVault(_vault).setTokenConfig(
            _token,
            tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            isStable,
            isShortable
        );

        IVault(_vault).setBufferAmount(_token, _bufferAmount);

        IVault(_vault).setMaxUsdAmount(_token, _maxUsdAmount);
    }

    /// @notice Set Max Global Short Size
    /// @param _vault The vault address
    /// @param _token The token to set the max short size for
    /// @param _amount The max short size for the token
    function setMaxGlobalShortSize(
        address _vault,
        address _token,
        uint256 _amount
    ) external onlyAdmin {
        IVault(_vault).setMaxGlobalShortSize(_token, _amount);
    }

    /// @notice Set `_vault` (vault) to be swap enabled: `_isSwapEnabled`
    /// @param _vault The vault address
    /// @param _isSwapEnabled True to enable swaps, false otherwise
    function setIsSwapEnabled(address _vault, bool _isSwapEnabled)
        external
        onlyAdminOrHandler
    {
        IVault(_vault).setIsSwapEnabled(_isSwapEnabled);
    }

    /// @notice Set the vault utils address to `_vaultUtils`
    /// @param _vault The vault address
    /// @param _vaultUtils The vault utils address
    function setVaultUtils(address _vault, IVaultUtils _vaultUtils)
        external
        onlyAdmin
    {
        IVault(_vault).setVaultUtils(_vaultUtils);
    }

    /// @notice Set the max gas price for `_vault` to `_maxGasPrice`
    /// @param _vault The vault address
    /// @param _maxGasPrice The max gas price for the vault
    function setMaxGasPrice(address _vault, uint256 _maxGasPrice)
        external
        onlyAdmin
    {
        if (_maxGasPrice < _MAX_GAS_PRICE_VALIDATION) {
            revert InvalidMaxGasPrice();
        }
        IVault(_vault).setMaxGasPrice(_maxGasPrice);
    }

    /// @notice Withdraw fees from `_vault` to `_receiver`
    /// @param _vault The vault address
    /// @param _token The token to withdraw
    /// @param _receiver The address to receive the fees
    function withdrawFees(
        address _vault,
        address _token,
        address _receiver
    ) external onlyAdmin {
        IVault(_vault).withdrawFees(_token, _receiver);
    }

    /// @notice Set the vault in private liquidation mode: `_inPrivateLiquidationMode`
    /// @param _vault The vault address
    /// @param _inPrivateLiquidationMode True to enable private liquidation, false otherwise
    function setInPrivateLiquidationMode(
        address _vault,
        bool _inPrivateLiquidationMode
    ) external onlyAdmin {
        IVault(_vault).setInPrivateLiquidationMode(_inPrivateLiquidationMode);
    }

    /// @notice Set `_liquidator` as a liquidator for `_vault`: `_isActive`
    /// @param _vault The vault address
    /// @param _liquidator The liquidator address
    /// @param _isActive True to enable liquidator, false otherwise
    function setLiquidator(
        address _vault,
        address _liquidator,
        bool _isActive
    ) external onlyAdmin {
        IVault(_vault).setLiquidator(_liquidator, _isActive);
    }

    /// @notice Set the vault price feed address to `_priceFeed`
    /// @param _vault The vault address
    /// @param _priceFeed The price feed address
    function setPriceFeed(address _vault, address _priceFeed)
        external
        onlyAdmin
    {
        bytes32 action = keccak256(
            abi.encodePacked("setPriceFeed", _vault, _priceFeed)
        );
        _validateAction(action);
        _clearAction(action);
        IVault(_vault).setPriceFeed(_priceFeed);
    }

    /// @notice Signal a vault setTokenConfig action
    /// @param _vault The vault address
    /// @param _token The token to set the config for
    /// @param _tokenDecimals The token decimals
    /// @param _tokenWeight The token weight
    /// @param _minProfitBps The min profit basis points
    /// @param _isStable True if the token is a stablecoin, false otherwise
    /// @param _isShortable True if the token is shortable, false otherwise
    function signalVaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        bool _isStable,
        bool _isShortable
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "vaultSetTokenConfig",
                _vault,
                _token,
                _tokenDecimals,
                _tokenWeight,
                _minProfitBps,
                _isStable,
                _isShortable
            )
        );

        _setPendingAction(action);

        emit SignalVaultSetTokenConfig(
            _vault,
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _isStable,
            _isShortable
        );
    }

    /// @notice Set a token's configuration variables
    /// @param _vault The vault address
    /// @param _token The token to set the config for
    /// @param _tokenDecimals The token decimals
    /// @param _tokenWeight The token weight
    /// @param _minProfitBps The min profit basis points
    /// @param _isStable True if the token is a stablecoin, false otherwise
    /// @param _isShortable True if the token is shortable, false otherwise
    function vaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        bool _isStable,
        bool _isShortable
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "vaultSetTokenConfig",
                _vault,
                _token,
                _tokenDecimals,
                _tokenWeight,
                _minProfitBps,
                _isStable,
                _isShortable
            )
        );

        _validateAction(action);
        _clearAction(action);

        IVault(_vault).setTokenConfig(
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _isStable,
            _isShortable
        );
    }

    /// @notice Remove `_account` as an admin for `_token`
    /// @param _token The token address
    /// @param _account The account to remove as an admin
    function removeAdmin(address _token, address _account) external onlyAdmin {
        IYieldToken(_token).removeAdmin(_account);
    }

    /// @notice Set `_priceFeed` (Price Feed) to be AMM enabled: `_isEnabled`
    /// @param _priceFeed The price feed address
    /// @param _isEnabled True to enable AMM, false otherwise
    function setIsAmmEnabled(address _priceFeed, bool _isEnabled)
        external
        onlyAdmin
    {
        IVaultPriceFeed(_priceFeed).setIsAmmEnabled(_isEnabled);
    }

    /// @notice Set `_priceFeed` (Price Feed) to be secondary price enabled: `_isEnabled`
    /// @param _priceFeed The price feed address
    /// @param _isEnabled True to enable secondary price, false otherwise
    function setIsSecondaryPriceEnabled(address _priceFeed, bool _isEnabled)
        external
        onlyAdminOrHandler
    {
        IVaultPriceFeed(_priceFeed).setIsSecondaryPriceEnabled(_isEnabled);
    }

    /// @notice Set the max strict price deviation for `_priceFeed` (Price Feed) to `_maxStrictPriceDeviation`
    /// @param _priceFeed The price feed address
    /// @param _maxStrictPriceDeviation The max strict price deviation
    function setMaxStrictPriceDeviation(
        address _priceFeed,
        uint256 _maxStrictPriceDeviation
    ) external onlyAdminOrHandler {
        IVaultPriceFeed(_priceFeed).setMaxStrictPriceDeviation(
            _maxStrictPriceDeviation
        );
    }

    /// @notice Set `_priceFeed` to use V2 AMM pricing: `_useV2Pricing`
    /// @param _priceFeed The price feed address
    /// @param _useV2Pricing True to enable V2 price, false otherwise
    function setUseV2Pricing(address _priceFeed, bool _useV2Pricing)
        external
        onlyAdminOrHandler
    {
        IVaultPriceFeed(_priceFeed).setUseV2Pricing(_useV2Pricing);
    }

    /// @notice Set the adjustment
    /// @param _priceFeed The price feed address
    /// @param _token The token address
    /// @param _isAdditive True if the adjustment is additive, false otherwise
    /// @param _adjustmentBps The adjustment in basis points
    function setAdjustment(
        address _priceFeed,
        address _token,
        bool _isAdditive,
        uint256 _adjustmentBps
    ) external onlyAdminOrHandler {
        IVaultPriceFeed(_priceFeed).setAdjustment(
            _token,
            _isAdditive,
            _adjustmentBps
        );
    }

    function setSpreadBasisPoints(
        address _priceFeed,
        address _token,
        uint8 _spreadBasisPoints
    ) external onlyAdminOrHandler {
        IVaultPriceFeed(_priceFeed).setSpreadBasisPoints(
            _token,
            _spreadBasisPoints
        );
    }

    function setSpreadThresholdBasisPoints(
        address _priceFeed,
        uint256 _spreadThresholdBasisPoints
    ) external onlyAdminOrHandler {
        IVaultPriceFeed(_priceFeed).setSpreadThresholdBasisPoints(
            _spreadThresholdBasisPoints
        );
    }

    function setPriceSampleSpace(address _priceFeed, uint256 _priceSampleSpace)
        external
        onlyAdminOrHandler
    {
        require(_priceSampleSpace <= 5, "Invalid _priceSampleSpace");
        IVaultPriceFeed(_priceFeed).setPriceSampleSpace(_priceSampleSpace);
    }

    /// @notice Set `_fastPriceFeed` (FastPriceFeed) to be spread enabled: `_isSpreadEnabled`
    /// @param _fastPriceFeed The fast price feed address
    /// @param _isSpreadEnabled True to enable spreads, false otherwise
    function setIsSpreadEnabled(address _fastPriceFeed, bool _isSpreadEnabled)
        external
        onlyAdminOrHandler
    {
        IFastPriceFeed(_fastPriceFeed).setIsSpreadEnabled(_isSpreadEnabled);
    }

    function setTier(
        address _referralStorage,
        uint256 _tierId,
        uint256 _totalRebate,
        uint256 _discountShare
    ) external onlyAdminOrHandler {
        IReferralStorage(_referralStorage).setTier(
            _tierId,
            _totalRebate,
            _discountShare
        );
    }

    function setReferrerTier(
        address _referralStorage,
        address _referrer,
        uint256 _tierId
    ) external onlyAdminOrHandler {
        IReferralStorage(_referralStorage).setReferrerTier(_referrer, _tierId);
    }

    function govSetCodeOwner(
        address _referralStorage,
        bytes32 _code,
        address _newAccount
    ) external onlyAdminOrHandler {
        IReferralStorage(_referralStorage).govSetCodeOwner(_code, _newAccount);
    }

    function setInPrivateTransferMode(
        address _token,
        bool _inPrivateTransferMode
    ) external onlyAdmin {
        if (excludedTokens[_token]) {
            // excludedTokens can only have their transfers enabled
            if (_inPrivateTransferMode) {
                revert InvalidInPrivateTransferMode();
            }
        }

        IBaseToken(_token).setInPrivateTransferMode(_inPrivateTransferMode);
    }

    function managedSetHandler(
        address _target,
        address _handler,
        bool _isActive
    ) external override onlyRewardManager {
        IHandlerTarget(_target).setHandler(_handler, _isActive);
    }

    function managedSetMinter(
        address _target,
        address _minter,
        bool _isActive
    ) external override onlyRewardManager {
        IMintable(_target).setMinter(_minter, _isActive);
    }

    function transferIn(
        address _sender,
        address _token,
        uint256 _amount
    ) external onlyAdmin {
        IERC20(_token).transferFrom(_sender, address(this), _amount);
    }

    function signalApprove(
        address _token,
        address _spender,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount)
        );
        _setPendingAction(action);
        emit SignalApprove(_token, _spender, _amount, action);
    }

    function approve(
        address _token,
        address _spender,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount)
        );
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).approve(_spender, _amount);
    }

    function signalWithdrawToken(
        address _target,
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "withdrawToken",
                _target,
                _token,
                _receiver,
                _amount
            )
        );
        _setPendingAction(action);
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
    }

    function withdrawToken(
        address _target,
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "withdrawToken",
                _target,
                _token,
                _receiver,
                _amount
            )
        );
        _validateAction(action);
        _clearAction(action);
        IBaseToken(_target).withdrawToken(_token, _receiver, _amount);
    }

    function signalMint(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("mint", _token, _receiver, _amount)
        );
        _setPendingAction(action);
        emit SignalMint(_token, _receiver, _amount, action);
    }

    function processMint(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("mint", _token, _receiver, _amount)
        );
        _validateAction(action);
        _clearAction(action);

        _mint(_token, _receiver, _amount);
    }

    function signalSetOwner(address _target, address _owner)
        external
        override
        onlyAdmin
    {
        bytes32 action = keccak256(
            abi.encodePacked("setOwner", _target, _owner)
        );
        _setPendingAction(action);
        emit SignalSetOwner(_target, _owner, action);
    }

    function setOwner(address _target, address _owner) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setOwner", _target, _owner)
        );
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).transferOwnership(_owner);
    }

    /// @notice Signal an action to set `_handler` as a handler for `_target`: `_isActive`
    /// @param _target The contract to set the handler for
    /// @param _handler The handler to set
    /// @param _isActive True to enable the handler, false otherwise
    function signalSetHandler(
        address _target,
        address _handler,
        bool _isActive
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setHandler", _target, _handler, _isActive)
        );
        _setPendingAction(action);
        emit SignalSetHandler(_target, _handler, _isActive, action);
    }

    /// @notice Set `_handler` as a handler for `_target`: `_isActive`
    /// @param _target The contract to set the handler for
    /// @param _handler The handler to set
    /// @param _isActive True to enable the handler, false otherwise
    function setHandler(
        address _target,
        address _handler,
        bool _isActive
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("setHandler", _target, _handler, _isActive)
        );
        _validateAction(action);
        _clearAction(action);
        IHandlerTarget(_target).setHandler(_handler, _isActive);
    }

    /// @notice Signal an action to set the vault price feed
    /// @param _vault The vault address
    /// @param _priceFeed The price feed address
    function signalSetPriceFeed(address _vault, address _priceFeed)
        external
        onlyAdmin
    {
        bytes32 action = keccak256(
            abi.encodePacked("setPriceFeed", _vault, _priceFeed)
        );
        _setPendingAction(action);
        emit SignalSetPriceFeed(_vault, _priceFeed, action);
    }

    /// @notice Signal an action to add a plugin to the router
    /// @param _router The router address
    /// @param _plugin The plugin to add
    function signalAddPlugin(address _router, address _plugin)
        external
        onlyAdmin
    {
        bytes32 action = keccak256(
            abi.encodePacked("addPlugin", _router, _plugin)
        );
        _setPendingAction(action);
        emit SignalAddPlugin(_router, _plugin, action);
    }

    /// @notice Add a plugin to the router
    /// @param _router The router address
    /// @param _plugin The plugin to add
    function addPlugin(address _router, address _plugin) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("addPlugin", _router, _plugin)
        );
        _validateAction(action);
        _clearAction(action);
        IRouter(_router).addPlugin(_plugin);
    }

    /// @notice Signal an action to set the price feed watcher
    /// @param _fastPriceFeed The fast price feed
    /// @param _account The price feed watcher
    /// @param _isActive Whether `_account` is an active price feed watcher
    function signalSetPriceFeedWatcher(
        address _fastPriceFeed,
        address _account,
        bool _isActive
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "setPriceFeedWatcher",
                _fastPriceFeed,
                _account,
                _isActive
            )
        );
        _setPendingAction(action);
        emit SignalSetPriceFeedWatcher(_fastPriceFeed, _account, _isActive);
    }

    /// @notice Set the price feed watcher
    /// @param _fastPriceFeed The fast price feed
    /// @param _account The price feed watcher
    /// @param _isActive Whether `_account` is an active price feed watcher
    function setPriceFeedWatcher(
        address _fastPriceFeed,
        address _account,
        bool _isActive
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "setPriceFeedWatcher",
                _fastPriceFeed,
                _account,
                _isActive
            )
        );
        _validateAction(action);
        _clearAction(action);
        IFastPriceFeed(_fastPriceFeed).setSigner(_account, _isActive);
    }

    /// @notice Signal a price feed setTokenConfig action
    /// @param _vaultPriceFeed The vault price feed address
    /// @param _token The token to set the config for
    /// @param _priceFeed The token price feed address
    /// @param _priceDecimals The decimals of the price feed
    /// @param _isStrictStable True if the token is a strict stablecoin, false otherwise
    function signalPriceFeedSetTokenConfig(
        address _vaultPriceFeed,
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "priceFeedSetTokenConfig",
                _vaultPriceFeed,
                _token,
                _priceFeed,
                _priceDecimals,
                _isStrictStable
            )
        );

        _setPendingAction(action);

        emit SignalPriceFeedSetTokenConfig(
            _vaultPriceFeed,
            _token,
            _priceFeed,
            _priceDecimals,
            _isStrictStable
        );
    }

    /// @notice Set a price feed's token configuration variables
    /// @param _vaultPriceFeed The vault price feed address
    /// @param _token The token to set the config for
    /// @param _priceFeed The token price feed address
    /// @param _priceDecimals The decimals of the price feed
    /// @param _isStrictStable True if the token is a strict stablecoin, false otherwise
    function priceFeedSetTokenConfig(
        address _vaultPriceFeed,
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "priceFeedSetTokenConfig",
                _vaultPriceFeed,
                _token,
                _priceFeed,
                _priceDecimals,
                _isStrictStable
            )
        );

        _validateAction(action);
        _clearAction(action);

        IVaultPriceFeed(_vaultPriceFeed).setTokenConfig(
            _token,
            _priceFeed,
            _priceDecimals,
            _isStrictStable
        );
    }

    function _mint(
        address _token,
        address _receiver,
        uint256 _amount
    ) private {
        IMintable mintable = IMintable(_token);

        if (!mintable.isMinter(address(this))) {
            mintable.setMinter(address(this), true);
        }

        mintable.mint(_receiver, _amount);
        if (IERC20(_token).totalSupply() > maxTokenSupply) {
            revert MaxTokenSupplyExceeded();
        }
    }

    function _setPendingAction(bytes32 _action) private {
        pendingActions[_action] = block.timestamp + buffer;
        emit SignalPendingAction(_action);
    }

    function _clearAction(bytes32 _action) private {
        if (pendingActions[_action] == 0) {
            revert InvalidAction();
        }
        delete pendingActions[_action];
        emit ClearAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        if (pendingActions[_action] == 0) {
            revert InvalidAction();
        }
        if (pendingActions[_action] >= block.timestamp) {
            revert TimeNotPassed();
        }
    }
}
