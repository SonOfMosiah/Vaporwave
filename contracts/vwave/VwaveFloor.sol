//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../tokens/interfaces/IMintable.sol";
import "../access/TokenManager.sol";

/// Sender is not a valid handler
error InvalidHandler();
error InvalidBackedSupply();
error InvalidMintMultiplier();
error InvalidAmount();
error InsufficientAmountOut();
error MaxCostExceeded();

/// @title Vaporwve VWAVE floor
contract VwaveFloor is ReentrancyGuard, TokenManager {
    using SafeERC20 for IERC20;

    uint16 public constant BURN_BASIS_POINTS = 9000;
    /// Helper to avoid truncation errors in basis points calculations
    uint16 public constant BASIS_POINTS_DIVISOR = 10000;

    uint128 public constant PRICE_PRECISION = 1e30;

    /// VWAVE token address
    address public vwave;
    /// Reserve token address
    address public reserveToken;
    uint256 public backedSupply;
    uint256 public baseMintPrice;
    uint256 public mintMultiplier;
    uint256 public mintedSupply;
    uint256 public multiplierPrecision;

    /// Mapping of handlers
    mapping(address => bool) public isHandler;

    modifier onlyHandler() {
        if (!isHandler[msg.sender]) {
            revert InvalidHandler();
        }
        _;
    }

    constructor(
        address _vwave,
        address _reserveToken,
        uint256 _backedSupply,
        uint256 _baseMintPrice,
        uint256 _mintMultiplier,
        uint256 _multiplierPrecision,
        uint256 _minAuthorizations
    ) TokenManager(_minAuthorizations) {
        vwave = _vwave;

        reserveToken = _reserveToken;
        backedSupply = _backedSupply;

        baseMintPrice = _baseMintPrice;
        mintMultiplier = _mintMultiplier;
        multiplierPrecision = _multiplierPrecision;
    }

    /// @notice Set `_handler` as a handler: `_isHandler`
    /// @param _handler The address of the handler
    /// @param _isHandler True if the handler is to be added, false if it is to be removed
    function setHandler(address _handler, bool _isHandler) external onlyAdmin {
        isHandler[_handler] = _isHandler;
    }

    /// @notice Set the backed supply
    /// @dev Backed supply can only increase
    /// @param _backedSupply The new backed supply
    function setBackedSupply(uint256 _backedSupply) external onlyAdmin {
        if (_backedSupply <= backedSupply) {
            revert InvalidBackedSupply();
        }
        backedSupply = _backedSupply;
    }

    /// @notice Set the mint multiplier
    /// @dev Mint multiplier can only increase
    /// @param _mintMultiplier The new mint multiplier
    function setMintMultiplier(uint256 _mintMultiplier) external onlyAdmin {
        if (_mintMultiplier <= mintMultiplier) {
            revert InvalidMintMultiplier();
        }
        mintMultiplier = _mintMultiplier;
    }

    /// @notice Transfer out vwave for reserve tokens
    /// @dev mint refers to increasing the circulating supply
    /// @dev the VWAVE tokens to be transferred out must be pre-transferred into this contract
    /// @param _amount The amount of vwave to transfer out
    /// @param _maxCost The maximum amount of reserve tokens to transfer to this contract
    /// @param _receiver The address to receive the VWAVE tokens
    function mint(
        uint256 _amount,
        uint256 _maxCost,
        address _receiver
    ) external onlyHandler nonReentrant returns (uint256) {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        uint256 currentMintPrice = getMintPrice();
        uint256 nextMintPrice = currentMintPrice +
            ((_amount * mintMultiplier) / multiplierPrecision);
        uint256 averageMintPrice = currentMintPrice + nextMintPrice / 2;

        uint256 cost = (_amount * averageMintPrice) / PRICE_PRECISION;
        if (cost > _maxCost) {
            revert MaxCostExceeded();
        }

        mintedSupply += _amount;
        backedSupply += _amount;

        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), cost);
        IERC20(vwave).transfer(_receiver, _amount);

        return cost;
    }

    /// @notice Burn VWAVE tokens and transfer reserve tokens to `_receiver`
    /// @param _amount The amount of VWAVE to burn
    /// @param _minOut The minimum amount of reserve tokens to transfer out
    /// @param _receiver The address to receive the reserve tokens
    function burn(
        uint256 _amount,
        uint256 _minOut,
        address _receiver
    ) external onlyHandler nonReentrant returns (uint256) {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        uint256 amountOut = getBurnAmountOut(_amount);
        if (amountOut < _minOut) {
            revert InsufficientAmountOut();
        }

        backedSupply -= _amount;

        IMintable(vwave).burn(msg.sender, _amount); // TODO: no burn function on vwave
        IERC20(reserveToken).safeTransfer(_receiver, amountOut);

        return amountOut;
    }

    /// @notice Initialize the token manager contract
    /// @param _signers An array of signers
    function initialize(address[] memory _signers) public override onlyAdmin {
        TokenManager.initialize(_signers);
    }

    /// @notice Get the mint price
    /// @return The mint price
    function getMintPrice() public view returns (uint256) {
        return
            baseMintPrice +
            ((mintedSupply * mintMultiplier) / multiplierPrecision);
    }

    /// @notice Get the burn amount out
    /// @param _amount The amount to be burned
    /// @return The burn amount out
    function getBurnAmountOut(uint256 _amount) public view returns (uint256) {
        uint256 balance = IERC20(reserveToken).balanceOf(address(this));
        return
            (_amount * balance * BURN_BASIS_POINTS) /
            backedSupply /
            BASIS_POINTS_DIVISOR;
    }
}
