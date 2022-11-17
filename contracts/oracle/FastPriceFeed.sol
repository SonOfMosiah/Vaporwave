// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/ISecondaryPriceFeed.sol";
import "./interfaces/IFastPriceFeed.sol";
import "./interfaces/IFastPriceEvents.sol";
import "../core/interfaces/IPositionRouter.sol";

/// Sender does not have permission to call the function
error Forbidden();
/// Must wait the cooldown period before updating
error UpdateCooldown();
/// Timestamp must be within the max time deviation range
error InvalidTimestamp();
/// Price duration cannot be greater than the max
error InvalidPriceDuration();
/// Array parameters are not the same length
error InvalidArrayLengths();
/// Caller has already cast this vote
error AlreadyVoted();
/// Contract is already initialized
error AlreadyInitialized();

// TODO finish NatSpec
/// @title Vaporwave Fast Price Feed
contract FastPriceFeed is ISecondaryPriceFeed, IFastPriceFeed, Ownable {
    /// The max price duration is 30 minutes (1800 seconds)
    uint16 public constant MAX_PRICE_DURATION = 30 minutes;
    /// Helper to avoid truncation errors in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;
    /// Helper to avoid truncation errors in price calculations
    uint128 public constant PRICE_PRECISION = 1e30;

    /// True if the contract is initialized
    bool public isInitialized;
    /// True if the feed is spread enabled
    bool public isSpreadEnabled;
    /// The fast price events contract address
    address public fastPriceEvents;

    /// The token manager address
    address public tokenManager;
    /// The position router address
    address public positionRouter;

    /// The timestamp of the last price update
    uint256 public override lastUpdatedAt;
    /// The block number of the last price update
    uint256 public override lastUpdatedBlock;

    /// The amount of time that the price remains valid (in seconds)
    uint256 public priceDuration;
    /// The minimum blocks between price updates
    uint256 public minBlockInterval;
    /// The maximum deviation for the update timestamp from the current timestamp
    uint256 public maxTimeDeviation;

    /// volatility basis points
    uint256 public volBasisPoints;
    /// max deviation from primary price
    uint256 public maxDeviationBasisPoints;
    /// The minimum authorizations to disable the fast price feed
    uint256 public minAuthorizations;
    /// The disable fast price vote counter
    uint256 public disableFastPriceVoteCount;

    /// Mapping of token prices
    mapping(address => uint256) public prices;

    /// Mapping of updaters
    mapping(address => bool) public isUpdater;
    /// Mapping of signers
    mapping(address => bool) public isSigner;
    /// Mapping of signer's vote for Fast Price
    mapping(address => bool) public disableFastPriceVotes;

    // array of tokens used in setCompactedPrices, saves L1 calldata gas costs
    address[] public tokens;
    // array of tokenPrecisions used in setCompactedPrices, saves L1 calldata gas costs
    // if the token price will be sent with 3 decimals, then tokenPrecision for that token
    // should be 10 ** 3
    uint256[] public tokenPrecisions; // TODO remove if not needed for Aurora

    /// @notice Emitted when a vote is cast to disable the fast price
    /// @param signer The address of the signer
    event DisableFastPrice(address signer);
    /// @notice Emitted when a vote is cast to enable the fast price
    /// @param signer The address of the signer
    event EnableFastPrice(address signer);

    /// Modified function can only be called by a valid signer
    modifier onlySigner() {
        if (!isSigner[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    /// Modified functions can only be called by a valid updater
    modifier onlyUpdater() {
        if (!isUpdater[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    /// Modified functions can only be called by the token manager
    modifier onlyTokenManager() {
        if (msg.sender != tokenManager) {
            revert Forbidden();
        }
        _;
    }

    constructor(
        uint256 _priceDuration,
        uint256 _minBlockInterval,
        uint256 _maxDeviationBasisPoints,
        address _fastPriceEvents,
        address _tokenManager,
        address _positionRouter
    ) {
        if (_priceDuration > MAX_PRICE_DURATION) {
            revert InvalidPriceDuration();
        }
        priceDuration = _priceDuration;
        minBlockInterval = _minBlockInterval;
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
        fastPriceEvents = _fastPriceEvents;
        tokenManager = _tokenManager;
        positionRouter = _positionRouter;
    }

    /// @notice Set the token manager to `_tokenManager`
    /// @param _tokenManager The new token manager address
    function setTokenManager(address _tokenManager) external onlyOwner {
        tokenManager = _tokenManager;
    }

    /// @notice Set `_account` as a signer: `_isActive`
    /// @param _account The address of the signer
    /// @param _isActive True if the signer is active, false otherwise
    function setSigner(address _account, bool _isActive)
        external
        override
        onlyOwner
    {
        isSigner[_account] = _isActive;
    }

    /// @notice Set `_account` as an updater: `_isActive`
    /// @param _account The address of the updater
    /// @param _isActive True if the updater is active, false otherwise
    function setUpdater(address _account, bool _isActive) external onlyOwner {
        isUpdater[_account] = _isActive;
    }

    /// @notice Set the fast price events address to `_fastPriceEvents`
    /// @param _fastPriceEvents The new fast price events address
    function setFastPriceEvents(address _fastPriceEvents) external onlyOwner {
        fastPriceEvents = _fastPriceEvents;
    }

    /// @notice Set the price duration to `_priceDuration`
    /// @dev The price duration must be less than or equal to the max price duration
    /// @param _priceDuration The new price duration
    function setPriceDuration(uint256 _priceDuration) external onlyOwner {
        if (_priceDuration > MAX_PRICE_DURATION) {
            revert InvalidPriceDuration();
        }
        priceDuration = _priceDuration;
    }

    /// @notice Set the minimum block interval to `_minBlockInterval`
    /// @param _minBlockInterval The new minimum block interval
    function setMinBlockInterval(uint256 _minBlockInterval) external onlyOwner {
        minBlockInterval = _minBlockInterval;
    }

    /// @notice Set the isSpreadEnabled variable to `_isSpreadEnabled`
    /// @param _isSpreadEnabled True if the spread is enabled, false otherwise
    function setIsSpreadEnabled(bool _isSpreadEnabled)
        external
        override
        onlyOwner
    {
        isSpreadEnabled = _isSpreadEnabled;
    }

    /// @notice Set the max time deviation from the block timestamp to `_maxTimeDeviation`
    /// @param _maxTimeDeviation The new max time deviation
    function setMaxTimeDeviation(uint256 _maxTimeDeviation) external onlyOwner {
        maxTimeDeviation = _maxTimeDeviation;
    }

    /// @notice Set the lastUpdatedAt variable to `_lastUpdatedAt`
    /// @param _lastUpdatedAt The new lastUpdatedAt value
    function setLastUpdatedAt(uint256 _lastUpdatedAt) external onlyOwner {
        lastUpdatedAt = _lastUpdatedAt;
    }

    /// @notice Set the volatility basis points to `_volBasisPoints`
    /// @param _volBasisPoints The new volatility basis points
    function setVolBasisPoints(uint256 _volBasisPoints) external onlyOwner {
        volBasisPoints = _volBasisPoints;
    }

    /// @notice Set the max deviation from the primary price to `_maxDeviationBasisPoints`
    /// @param _maxDeviationBasisPoints The new max deviation from the primary price
    function setMaxDeviationBasisPoints(uint256 _maxDeviationBasisPoints)
        external
        onlyOwner
    {
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
    }

    /// @notice Set the minimum authorizations to disable the fast price to `_minAuthorizations`
    /// @param _minAuthorizations The new minimum authorizations
    function setMinAuthorizations(uint256 _minAuthorizations)
        external
        onlyTokenManager
    {
        minAuthorizations = _minAuthorizations;
    }

    /// @notice Set the tokens and tokenPrecisions arrays
    /// @param _tokens The new tokens array
    /// @param _tokenPrecisions The new tokenPrecisions array
    function setTokens(
        address[] memory _tokens,
        uint256[] memory _tokenPrecisions
    ) external onlyOwner {
        if (_tokens.length != _tokenPrecisions.length) {
            revert InvalidArrayLengths();
        }
        tokens = _tokens;
        tokenPrecisions = _tokenPrecisions;
    }

    /// @notice Set the token prices
    /// @param _tokens The array of tokens
    /// @param _prices The array of prices
    /// @param _timestamp The timestamp of the prices
    function setPrices(
        address[] memory _tokens,
        uint256[] memory _prices,
        uint256 _timestamp
    ) external onlyUpdater {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;

            for (uint256 i = 0; i < _tokens.length; i++) {
                address token = _tokens[i];
                prices[token] = _prices[i];
                _emitPriceEvent(_fastPriceEvents, token, _prices[i]);
            }
        }
    }

    /// @notice Set the compacted prices
    /// @param _priceBitArray The new compacted prices array
    /// @param _timestamp The timestamp of the prices
    function setCompactedPrices(
        uint256[] memory _priceBitArray,
        uint256 _timestamp
    ) external onlyUpdater {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;

            for (uint256 i = 0; i < _priceBitArray.length; i++) {
                uint256 priceBits = _priceBitArray[i];

                for (uint256 j = 0; j < 8; j++) {
                    uint256 index = i * 8 + j;
                    if (index >= tokens.length) {
                        return;
                    }

                    uint256 startBit = 32 * j;
                    uint256 price = (priceBits >> startBit) & type(uint32).max;

                    address token = tokens[i * 8 + j];
                    uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                    uint256 adjustedPrice = (price * PRICE_PRECISION) /
                        tokenPrecision;
                    prices[token] = adjustedPrice;

                    _emitPriceEvent(_fastPriceEvents, token, adjustedPrice);
                }
            }
        }
    }

    /// @notice Set the prices with bits
    /// @param _priceBits The price bits
    /// @param _timestamp The timestamp of the update
    function setPricesWithBits(uint256 _priceBits, uint256 _timestamp)
        external
        onlyUpdater
    {
        _setPricesWithBits(_priceBits, _timestamp);
    }

    /// @notice Set
    function setPricesWithBitsAndExecute(
        uint256 _priceBits,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions
    ) external onlyUpdater {
        _setPricesWithBits(_priceBits, _timestamp);

        IPositionRouter _positionRouter = IPositionRouter(positionRouter);
        _positionRouter.executeIncreasePositions(
            _endIndexForIncreasePositions,
            payable(msg.sender)
        );
        _positionRouter.executeDecreasePositions(
            _endIndexForDecreasePositions,
            payable(msg.sender)
        );
    }

    function disableFastPrice() external onlySigner {
        if (disableFastPriceVotes[msg.sender]) {
            revert AlreadyVoted();
        }
        disableFastPriceVotes[msg.sender] = true;
        disableFastPriceVoteCount++;

        emit DisableFastPrice(msg.sender);
    }

    function enableFastPrice() external onlySigner {
        if (!disableFastPriceVotes[msg.sender]) {
            revert AlreadyVoted();
        }
        disableFastPriceVotes[msg.sender] = false;
        disableFastPriceVoteCount--;

        emit EnableFastPrice(msg.sender);
    }

    function getPrice(
        address _token,
        uint256 _refPrice,
        bool _maximise
    ) external view override returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > lastUpdatedAt + priceDuration) {
            return _refPrice;
        }

        uint256 fastPrice = prices[_token];
        if (fastPrice == 0) {
            return _refPrice;
        }

        uint256 maxPrice = (_refPrice *
            (BASIS_POINTS_DIVISOR + maxDeviationBasisPoints)) /
            BASIS_POINTS_DIVISOR;
        uint256 minPrice = (_refPrice *
            (BASIS_POINTS_DIVISOR - maxDeviationBasisPoints)) /
            BASIS_POINTS_DIVISOR;

        if (favorFastPrice()) {
            if (fastPrice >= minPrice && fastPrice <= maxPrice) {
                if (_maximise) {
                    if (_refPrice > fastPrice) {
                        uint256 volPrice = (fastPrice *
                            (BASIS_POINTS_DIVISOR + volBasisPoints)) /
                            BASIS_POINTS_DIVISOR;
                        // the volPrice should not be more than _refPrice
                        return volPrice > _refPrice ? _refPrice : volPrice;
                    }
                    return fastPrice;
                }

                if (_refPrice < fastPrice) {
                    uint256 volPrice = (fastPrice *
                        (BASIS_POINTS_DIVISOR - volBasisPoints)) /
                        BASIS_POINTS_DIVISOR;
                    // the volPrice should not be less than _refPrice
                    return volPrice < _refPrice ? _refPrice : volPrice;
                }

                return fastPrice;
            }
        }

        if (_maximise) {
            if (_refPrice > fastPrice) {
                return _refPrice;
            }
            return fastPrice > maxPrice ? maxPrice : fastPrice;
        }

        if (_refPrice < fastPrice) {
            return _refPrice;
        }
        return fastPrice < minPrice ? minPrice : fastPrice;
    }

    function initialize(
        uint256 _minAuthorizations,
        address[] memory _signers,
        address[] memory _updaters
    ) public onlyOwner {
        if (isInitialized) {
            revert AlreadyInitialized();
        }
        isInitialized = true;

        minAuthorizations = _minAuthorizations;

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }

        for (uint256 i = 0; i < _updaters.length; i++) {
            address updater = _updaters[i];
            isUpdater[updater] = true;
        }
    }

    function favorFastPrice() public view returns (bool) {
        if (isSpreadEnabled) {
            return false;
        }

        if (disableFastPriceVoteCount >= minAuthorizations) {
            return false;
        }

        return true;
    }

    function _setPricesWithBits(uint256 _priceBits, uint256 _timestamp)
        private
    {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;

            for (uint256 j = 0; j < 8; j++) {
                uint256 index = j;
                if (index >= tokens.length) {
                    return;
                }

                uint256 startBit = 32 * j;
                uint256 price = (_priceBits >> startBit) & type(uint32).max;

                address token = tokens[j];
                uint256 tokenPrecision = tokenPrecisions[j];
                uint256 adjustedPrice = (price * PRICE_PRECISION) /
                    tokenPrecision;
                prices[token] = adjustedPrice;

                _emitPriceEvent(_fastPriceEvents, token, adjustedPrice);
            }
        }
    }

    function _emitPriceEvent(
        address _fastPriceEvents,
        address _token,
        uint256 _price
    ) private {
        if (_fastPriceEvents == address(0)) {
            return;
        }

        IFastPriceEvents(_fastPriceEvents).emitPriceEvent(_token, _price);
    }

    function _setLastUpdatedValues(uint256 _timestamp) private returns (bool) {
        if (minBlockInterval > 0) {
            if (block.number - lastUpdatedBlock < minBlockInterval) {
                revert UpdateCooldown();
            }
        }

        if (
            // solhint-disable-next-line not-rely-on-time
            _timestamp <= block.timestamp - maxTimeDeviation ||
            // solhint-disable-next-line not-rely-on-time
            _timestamp >= block.timestamp + maxTimeDeviation
        ) {
            revert InvalidTimestamp();
        }

        // do not update prices if _timestamp is before the current lastUpdatedAt value
        if (_timestamp < lastUpdatedAt) {
            return false;
        }

        lastUpdatedAt = _timestamp;
        lastUpdatedBlock = block.number;

        return true;
    }
}
