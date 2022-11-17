// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../oracle/interfaces/ISecondaryPriceFeed.sol";
import "../amm/interfaces/IPancakePair.sol";
import "../amm/interfaces/IUniswapV2Oracle.sol";

/// Sender does not have permission to call this function
error Forbidden();
/// Must wait for the adjustment interval to pass before calling this function
error AdjustmentCooldown();
/// Adjustment basis points cannot be greater than the max
error InvalidAdjustmentBps();
/// Spread basis points cannot be greater than the max
error InvalidSpreadBasisPoints();
/// The price sample space must be greater than 0
error InvalidPriceSampleSpace();
/// Not a valid price feed
error InvalidPriceFeed();
/// Price must be greater than 0
error InvalidPrice();

/// @title Vaporwave Vault Price Feed
contract VaultPriceFeed is Ownable, IVaultPriceFeed {
    /// @notice The max spread basis points is 50
    uint8 public constant MAX_SPREAD_BASIS_POINTS = 50;
    /// @notice The max basis points adjustment is 20
    uint8 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;
    /// @notice The max adjustment interval is 2 hours (7,200 seconds)
    uint16 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours; // 7200 seconds
    /// @notice Factor used to avoid decimals in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;
    /// @notice Calculation helper to avoid truncation errors
    uint128 public constant PRICE_PRECISION = 1e30;
    /// @notice Calculation helper to avoid truncation errors
    uint128 public constant ONE_USD = PRICE_PRECISION;

    /// @notice If the price feed is AMM pricing enabled
    bool public isAmmEnabled = true;
    /// @notice If the price feed is secondary pricing enabled
    bool public isSecondaryPriceEnabled = true;
    /// @notice If the price feed can use v2 pricing
    bool public useV2Pricing;

    /// @notice The number of rounds to sample from the price feed
    uint256 public priceSampleSpace = 3;
    /// @notice Basis points for AMM price deviation allowance
    uint256 public spreadThresholdBasisPoints = 30;
    /// @notice The max allowed price deviation for strict stablecoins to return 1 USD
    uint256 public maxStrictPriceDeviation;
    /// @notice The address of the secondary price feed
    address public secondaryPriceFeed;

    /// @notice Mapping of tokens to amm oracles
    mapping(address => address) public ammOracles;

    /// @notice Mapping of tokens to price feeds
    mapping(address => address) public priceFeeds;
    /// @notice Mapping of price feeds to decimals
    mapping(address => uint256) public priceDecimals;
    /// @notice Mapping of tokens to their the spread basis points
    mapping(address => uint8) public spreadBasisPoints;

    /// @dev Chainlink can return prices for stablecoins
    /// @dev that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    /// @dev we use strictStableTokens to cap the price to 1 USD
    /// @dev this allows us to configure stablecoins like DAI as being a stableToken
    /// @dev while not being a strictStableToken
    /// @notice Mapping of strict stablecoins
    mapping(address => bool) public strictStableTokens;
    /// Mapping of tokens to their adjustment basis points
    mapping(address => uint256) public override adjustmentBasisPoints;
    /// True if token adjustment is additive, false if deductive
    mapping(address => bool) public override isAdjustmentAdditive;
    /// Mapping of tokens to their last adjustment time
    mapping(address => uint256) public lastAdjustmentTimings;

    /// @notice Set the adjustment factors for `_token`
    /// @param _token The token to set the adjustment factors for
    /// @param _isAdditive True if the adjustment is additive, false if subtractive
    /// @param _adjustmentBps The adjustment basis points
    function setAdjustment(
        address _token,
        bool _isAdditive,
        uint256 _adjustmentBps
    ) external override onlyOwner {
        if (
            lastAdjustmentTimings[_token] + MAX_ADJUSTMENT_INTERVAL >=
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        ) {
            revert AdjustmentCooldown();
        }
        if (_adjustmentBps > MAX_ADJUSTMENT_BASIS_POINTS) {
            revert InvalidAdjustmentBps();
        }
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        // solhint-disable-next-line not-rely-on-time
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    /// @notice Enable or disable `_useV2Pricing` the price feed from using V2 pricing
    /// @param _useV2Pricing Whether to enable or disable the V2 pricing for the feed
    function setUseV2Pricing(bool _useV2Pricing) external override onlyOwner {
        useV2Pricing = _useV2Pricing;
    }

    /// @notice Enable or disable `_isEnabled` the price feed from using AMM aggregate pricing
    /// @param _isEnabled Whether to enable or disable the AMM pricing for the feed
    function setIsAmmEnabled(bool _isEnabled) external override onlyOwner {
        isAmmEnabled = _isEnabled;
    }

    /// @notice Enable or disable `_isEnabled` the price feed from using secondary pricing
    /// @param _isEnabled Whether to enable or disable the secondary pricing for the feed
    function setIsSecondaryPriceEnabled(bool _isEnabled)
        external
        override
        onlyOwner
    {
        isSecondaryPriceEnabled = _isEnabled;
    }

    /// @notice Set the secondary price feed to `_secondaryPriceFeed`
    /// @param _secondaryPriceFeed The address of the secondary price feed
    function setSecondaryPriceFeed(address _secondaryPriceFeed)
        external
        onlyOwner
    {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    /// @notice Set the AMM oracle for `_token` to `_ammOracle`
    /// @param _token The token to set the AMM oracle for
    /// @param _ammOracle The address of the AMM oracle
    function setAmmOracle(address _token, address _ammOracle)
        external
        onlyOwner
    {
        ammOracles[_token] = _ammOracle;
    }

    /// @notice Set the spread basis points for `_token` to `_spreadBasisPoints`
    /// @param _token The token to set the spread basis points for
    /// @param _spreadBasisPoints The spread basis points for the token
    function setSpreadBasisPoints(address _token, uint8 _spreadBasisPoints)
        external
        override
        onlyOwner
    {
        if (_spreadBasisPoints > MAX_SPREAD_BASIS_POINTS) {
            revert InvalidSpreadBasisPoints();
        }
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    /// @notice Set the spread threshold basis points
    /// @param _spreadThresholdBasisPoints The spread threshold basis points
    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints)
        external
        override
        onlyOwner
    {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    /// @notice Set the price sample space to `_priceSampleSpace`
    /// @param _priceSampleSpace The price sample space
    function setPriceSampleSpace(uint256 _priceSampleSpace)
        external
        override
        onlyOwner
    {
        if (_priceSampleSpace == 0) {
            revert InvalidPriceSampleSpace();
        }
        priceSampleSpace = _priceSampleSpace;
    }

    /// @notice Set the max price deviation for strict stablecoins to `_maxStrictPriceDeviation`
    /// @param _maxStrictPriceDeviation The max strict price deviation
    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation)
        external
        override
        onlyOwner
    {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    /// @notice Set the token configurations variables for `_token`
    /// @param _token The token address
    /// @param _priceFeed The price feed address
    /// @param _priceDecimals The decimals of the price feed
    /// @param _isStrictStable True if the token is a strict stablecoin, false otherwise
    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external override onlyOwner {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
    }

    /// @notice Get the price for `_token`
    /// @param _token The token address
    /// @param _maximise True if the price should be maximized, false to minimize
    /// @param _includeAmmPrice True to include AMM pricing, false to exclude
    function getPrice(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) public view override returns (uint256) {
        uint256 price = useV2Pricing
            ? getPriceV2(_token, _maximise, _includeAmmPrice)
            : getPriceV1(_token, _maximise, _includeAmmPrice);

        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price =
                    (price * (BASIS_POINTS_DIVISOR + adjustmentBps)) /
                    BASIS_POINTS_DIVISOR;
            } else {
                price =
                    (price * (BASIS_POINTS_DIVISOR - adjustmentBps)) /
                    BASIS_POINTS_DIVISOR;
            }
        }

        return price;
    }

    /// @notice Get the price for `_token`
    /// @dev This function does not use v2 AMM pricing
    /// @param _token The token address
    /// @param _maximise True if the price should be maximized, false to minimize
    /// @param _includeAmmPrice True to include AMM pricing, false to exclude
    function getPriceV1(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (_includeAmmPrice && isAmmEnabled) {
            uint256 ammPrice = getAmmPrice(_token);
            if (ammPrice > 0) {
                if (_maximise && ammPrice > price) {
                    price = ammPrice;
                }
                if (!_maximise && ammPrice < price) {
                    price = ammPrice;
                }
            }
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price - ONE_USD : ONE_USD - price;
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return
                (price * (BASIS_POINTS_DIVISOR + _spreadBasisPoints)) /
                BASIS_POINTS_DIVISOR;
        }

        return
            (price * (BASIS_POINTS_DIVISOR - _spreadBasisPoints)) /
            BASIS_POINTS_DIVISOR;
    }

    /// @notice Get the price for `_token`
    /// @dev This function uses v2 AMM pricing
    /// @param _token The token address
    /// @param _maximise True if the price should be maximized, false to minimize
    /// @param _includeAmmPrice True to include AMM pricing, false to exclude
    function getPriceV2(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (_includeAmmPrice && isAmmEnabled) {
            price = getAmmPriceV2(_token, _maximise, price);
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price - ONE_USD : ONE_USD - price;
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return
                (price * (BASIS_POINTS_DIVISOR + _spreadBasisPoints)) /
                BASIS_POINTS_DIVISOR;
        }

        return
            (price * (BASIS_POINTS_DIVISOR - _spreadBasisPoints)) /
            BASIS_POINTS_DIVISOR;
    }

    /// @notice Get the amm price for `_token`
    /// @dev This function adds an additional boundary check between the primary price and the amm price
    /// @param _token The token address
    /// @param _maximise True if the price should be maximized, false to minimize
    /// @param _primaryPrice The primary price
    function getAmmPriceV2(
        address _token,
        bool _maximise,
        uint256 _primaryPrice
    ) public view returns (uint256) {
        uint256 ammPrice = getAmmPrice(_token);
        if (ammPrice == 0) {
            return _primaryPrice;
        }

        uint256 diff = ammPrice > _primaryPrice
            ? ammPrice - _primaryPrice
            : _primaryPrice - ammPrice;
        if (
            diff * BASIS_POINTS_DIVISOR <
            _primaryPrice * spreadThresholdBasisPoints
        ) {
            return _primaryPrice;
        }

        if (_maximise && ammPrice > _primaryPrice) {
            return ammPrice;
        }

        if (!_maximise && ammPrice < _primaryPrice) {
            return ammPrice;
        }

        return _primaryPrice;
    }

    /// @notice Get the primary price for `_token`
    /// @param _token The token address
    /// @param _maximise True if the price should be maximized, false to minimize
    function getPrimaryPrice(address _token, bool _maximise)
        public
        view
        override
        returns (uint256)
    {
        address priceFeedAddress = priceFeeds[_token];
        if (priceFeedAddress == address(0)) {
            revert InvalidPriceFeed();
        }

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        uint256 price = 0;
        uint80 roundId = priceFeed.latestRound();

        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) {
                break;
            }

            uint256 p;
            int256 _p;

            if (i == 0) {
                _p = priceFeed.latestAnswer();
            } else {
                (, _p, , , ) = priceFeed.getRoundData(roundId - i);
            }

            if (_p == 0) {
                revert InvalidPrice();
            }
            p = uint256(_p);

            if (price == 0) {
                price = p;
                continue;
            }

            if (_maximise && p > price) {
                price = p;
                continue;
            }

            if (!_maximise && p < price) {
                price = p;
            }
        }

        if (price == 0) {
            revert InvalidPrice();
        }
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        return (price * PRICE_PRECISION) / (10**_priceDecimals);
    }

    /// @notice Get the secondary price for `_token`
    /// @param _token The token address
    /// @param _referencePrice The reference price
    /// @param _maximise True if the price should be maximized, false to minimize
    function getSecondaryPrice(
        address _token,
        uint256 _referencePrice,
        bool _maximise
    ) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) {
            return _referencePrice;
        }
        return
            ISecondaryPriceFeed(secondaryPriceFeed).getPrice(
                _token,
                _referencePrice,
                _maximise
            );
    }

    /// @notice Get the amm price for `_token`
    /// @dev Set isAmmEnabled to true to apply TWAP amm oracle pricing
    /// @param _token The token address
    function getAmmPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        if (ammOracles[_token] != address(0)) {
            return
                IUniswapV2Oracle(ammOracles[_token]).consult(_token, 1e18) *
                PRICE_PRECISION;
        }

        return 0;
    }
}
