// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IVlpManager.sol";

/// Contract is already initialized
error AlreadyInitialized();
/// The sender must be `weth`
error InvalidSender();
/// Receiver has staked tokens or cumulated rewards
error InvalidReceiver();
/// Amount must be greater than 0
error InvalidAmount();
/// Value must be greater than 0
error InvalidValue();
/// The sender of the transfer has vested tokens
error SenderHasVestedTokens();
/// The transfer has not been signalled
error TransferNotSignalled();

/// @title Vaporwave Reward Router
contract RewardRouterV2 is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    /// Wrapped Ether (WETH) token address
    address public weth;
    /// VWAVE token address
    address public vwave;
    /// EsVWAVE token address
    address public esVwave;
    address public bnVwave;

    /// VWAVE Liquidity Provider token
    address public vlp;

    address public stakedVwaveTracker;
    address public bonusVwaveTracker;
    address public feeVwaveTracker;

    address public stakedVlpTracker;
    address public feeVlpTracker;

    address public vlpManager;

    address public vwaveVester;
    address public vlpVester;

    mapping(address => address) public pendingReceivers;

    event StakeVwave(address account, address token, uint256 amount);
    event UnstakeVwave(address account, address token, uint256 amount);

    event StakeVlp(address account, uint256 amount);
    event UnstakeVlp(address account, uint256 amount);

    receive() external payable {
        if (msg.sender != weth) {
            revert InvalidSender();
        }
    }

    /// @notice Initialize the contract
    /// @dev Function can only be called once
    /// @param _weth Wrapped Ether (WETH) token address
    /// @param _vwave VWAVE token address
    /// @param _esVwave EsVWAVE token address
    /// @param _bnVwave BnVWAVE token address
    /// @param _vlp VWAVE Liquidity Provider token address
    /// @param _stakedVwaveTracker StakedVwaveTracker address
    /// @param _bonusVwaveTracker BonusVwaveTracker address
    /// @param _feeVwaveTracker FeeVwaveTracker address
    /// @param _feeVlpTracker FeeVlpTracker address
    /// @param _stakedVlpTracker StakedVlpTracker address
    /// @param _vlpManager VlpManager address
    /// @param _vwaveVester VWAVE Vester address
    /// @param _vlpVester VLP Vester address
    function initialize(
        address _weth,
        address _vwave,
        address _esVwave,
        address _bnVwave,
        address _vlp,
        address _stakedVwaveTracker,
        address _bonusVwaveTracker,
        address _feeVwaveTracker,
        address _feeVlpTracker,
        address _stakedVlpTracker,
        address _vlpManager,
        address _vwaveVester,
        address _vlpVester
    ) external onlyOwner {
        if (isInitialized) {
            revert AlreadyInitialized();
        }
        isInitialized = true;

        weth = _weth;

        vwave = _vwave;
        esVwave = _esVwave;
        bnVwave = _bnVwave;

        vlp = _vlp;

        stakedVwaveTracker = _stakedVwaveTracker;
        bonusVwaveTracker = _bonusVwaveTracker;
        feeVwaveTracker = _feeVwaveTracker;

        feeVlpTracker = _feeVlpTracker;
        stakedVlpTracker = _stakedVlpTracker;

        vlpManager = _vlpManager;

        vwaveVester = _vwaveVester;
        vlpVester = _vlpVester;
    }

    /// @notice Send `amount` of `_token` from this contract to `_account`
    /// @dev to help users who accidentally send their tokens to this contract
    /// @param _token The token to withdraw
    /// @param _account The account to receive the tokens
    /// @param _amount The amount of tokens to withdraw
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    /// @notice Stake VWAVE for an array of accounts
    /// @dev Save gas by staking VWAVE for multiple accounts at once
    /// @param _accounts An array of accounts to stake VWAVE for
    /// @param _amounts An array of amounts to stake for each account
    function batchStakeVwaveForAccounts(
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external nonReentrant onlyOwner {
        address _vwave = vwave;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeVwave(msg.sender, _accounts[i], _vwave, _amounts[i]);
        }
    }

    /// @notice Stake VWAVE for `_account`
    /// @param _account The account to stake VWAVE for
    /// @param _amount The amount of VWAVE to stake
    function stakeVwaveForAccount(address _account, uint256 _amount)
        external
        nonReentrant
        onlyOwner
    {
        _stakeVwave(msg.sender, _account, vwave, _amount);
    }

    /// @notice Stake VWAVE
    /// @param _amount The amount of VWAVE to stake
    function stakeVwave(uint256 _amount) external nonReentrant {
        _stakeVwave(msg.sender, msg.sender, vwave, _amount);
    }

    /// @notice Stake EsVWAVE
    /// @notice _amount The amount of EsVWAVE to stake
    function stakeEsVwave(uint256 _amount) external nonReentrant {
        _stakeVwave(msg.sender, msg.sender, esVwave, _amount);
    }

    /// @notice Unstake VWAVE
    /// @dev This will reduce the user's BnVWAVE
    /// @param _amount The amount of VWAVE to unstake
    function unstakeVwave(uint256 _amount) external nonReentrant {
        _unstakeVwave(msg.sender, vwave, _amount, true);
    }

    /// @notice Unstake EsVWAVE
    /// @dev This will reduce the user's BnVWAVE
    /// @param _amount The amount of EsVWAVE to unstake
    function unstakeEsVwave(uint256 _amount) external nonReentrant {
        _unstakeVwave(msg.sender, esVwave, _amount, true);
    }

    function mintAndStakeVlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdv,
        uint256 _minVlp
    ) external nonReentrant returns (uint256) {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        address account = msg.sender;
        uint256 vlpAmount = IVlpManager(vlpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdv,
            _minVlp
        );
        IRewardTracker(feeVlpTracker).stakeForAccount(
            account,
            account,
            vlp,
            vlpAmount
        );
        IRewardTracker(stakedVlpTracker).stakeForAccount(
            account,
            account,
            feeVlpTracker,
            vlpAmount
        );

        emit StakeVlp(account, vlpAmount);

        return vlpAmount;
    }

    function mintAndStakeVlpETH(uint256 _minUsdv, uint256 _minVlp)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        if (msg.value == 0) {
            revert InvalidValue();
        }

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(vlpManager, msg.value);

        address account = msg.sender;
        uint256 vlpAmount = IVlpManager(vlpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minUsdv,
            _minVlp
        );

        IRewardTracker(feeVlpTracker).stakeForAccount(
            account,
            account,
            vlp,
            vlpAmount
        );
        IRewardTracker(stakedVlpTracker).stakeForAccount(
            account,
            account,
            feeVlpTracker,
            vlpAmount
        );

        emit StakeVlp(account, vlpAmount);

        return vlpAmount;
    }

    function unstakeAndRedeemVlp(
        address _tokenOut,
        uint256 _vlpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        if (_vlpAmount == 0) {
            revert InvalidAmount();
        }

        address account = msg.sender;
        IRewardTracker(stakedVlpTracker).unstakeForAccount(
            account,
            feeVlpTracker,
            _vlpAmount,
            account
        );
        IRewardTracker(feeVlpTracker).unstakeForAccount(
            account,
            vlp,
            _vlpAmount,
            account
        );
        uint256 amountOut = IVlpManager(vlpManager).removeLiquidityForAccount(
            account,
            _tokenOut,
            _vlpAmount,
            _minOut,
            _receiver
        );

        emit UnstakeVlp(account, _vlpAmount);

        return amountOut;
    }

    function unstakeAndRedeemVlpETH(
        uint256 _vlpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        if (_vlpAmount == 0) {
            revert InvalidAmount();
        }

        address account = msg.sender;
        IRewardTracker(stakedVlpTracker).unstakeForAccount(
            account,
            feeVlpTracker,
            _vlpAmount,
            account
        );
        IRewardTracker(feeVlpTracker).unstakeForAccount(
            account,
            vlp,
            _vlpAmount,
            account
        );
        uint256 amountOut = IVlpManager(vlpManager).removeLiquidityForAccount(
            account,
            weth,
            _vlpAmount,
            _minOut,
            address(this)
        );

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeVlp(account, _vlpAmount);

        return amountOut;
    }

    /// @notice Claim accrued fees + EsVWAVE
    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeVwaveTracker).claimForAccount(account, account);
        IRewardTracker(feeVlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedVwaveTracker).claimForAccount(account, account);
        IRewardTracker(stakedVlpTracker).claimForAccount(account, account);
    }

    /// @notice Claim EsVWAVE from staked VWAVE and VLP
    function claimEsVwave() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedVwaveTracker).claimForAccount(account, account);
        IRewardTracker(stakedVlpTracker).claimForAccount(account, account);
    }

    /// @notice Claim accrued fees
    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeVwaveTracker).claimForAccount(account, account);
        IRewardTracker(feeVlpTracker).claimForAccount(account, account);
    }

    /// @notice Compound staked VWAVE and VLP
    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    /// @notice Compound staked VWAVE and VLP for `_account`
    /// @param _account The account to compound for
    function compoundForAccount(address _account)
        external
        nonReentrant
        onlyOwner
    {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimVwave,
        bool _shouldStakeVwave,
        bool _shouldClaimEsVwave,
        bool _shouldStakeEsVwave,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 vwaveAmount = 0;
        if (_shouldClaimVwave) {
            uint256 vwaveAmount0 = IVester(vwaveVester).claimForAccount(
                account,
                account
            );
            uint256 vwaveAmount1 = IVester(vlpVester).claimForAccount(
                account,
                account
            );
            vwaveAmount = vwaveAmount0 + vwaveAmount1;
        }

        if (_shouldStakeVwave && vwaveAmount > 0) {
            _stakeVwave(account, account, vwave, vwaveAmount);
        }

        uint256 esVwaveAmount = 0;
        if (_shouldClaimEsVwave) {
            uint256 esVwaveAmount0 = IRewardTracker(stakedVwaveTracker)
                .claimForAccount(account, account);
            uint256 esVwaveAmount1 = IRewardTracker(stakedVlpTracker)
                .claimForAccount(account, account);
            esVwaveAmount = esVwaveAmount0 + esVwaveAmount1;
        }

        if (_shouldStakeEsVwave && esVwaveAmount > 0) {
            _stakeVwave(account, account, esVwave, esVwaveAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnVwaveAmount = IRewardTracker(bonusVwaveTracker)
                .claimForAccount(account, account);
            if (bnVwaveAmount > 0) {
                IRewardTracker(feeVwaveTracker).stakeForAccount(
                    account,
                    account,
                    bnVwave,
                    bnVwaveAmount
                );
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeVwaveTracker).claimForAccount(
                    account,
                    address(this)
                );
                uint256 weth1 = IRewardTracker(feeVlpTracker).claimForAccount(
                    account,
                    address(this)
                );

                uint256 wethAmount = weth0 + weth1;
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeVwaveTracker).claimForAccount(
                    account,
                    account
                );
                IRewardTracker(feeVlpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts)
        external
        nonReentrant
        onlyOwner
    {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    /// @notice Signal a transfer to `_receiver`
    /// @dev Sender cannot have vested tokens
    /// @param _receiver The address to transfer to
    function signalTransfer(address _receiver) external nonReentrant {
        if (
            IERC20(vwaveVester).balanceOf(msg.sender) > 0 ||
            IERC20(vlpVester).balanceOf(msg.sender) > 0
        ) {
            revert SenderHasVestedTokens();
        }

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    /// @notice Accept a pending transfer from `_sender`
    /// @dev Sender cannot have vested tokens
    /// @param _sender The sender of the transfer
    function acceptTransfer(address _sender) external nonReentrant {
        if (
            IERC20(vwaveVester).balanceOf(_sender) > 0 ||
            IERC20(vlpVester).balanceOf(_sender) > 0
        ) {
            revert SenderHasVestedTokens();
        }

        address receiver = msg.sender;
        if (pendingReceivers[_sender] != receiver) {
            revert TransferNotSignalled();
        }

        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedVwave = IRewardTracker(stakedVwaveTracker)
            .depositBalances(_sender, vwave);
        if (stakedVwave > 0) {
            _unstakeVwave(_sender, vwave, stakedVwave, false);
            _stakeVwave(_sender, receiver, vwave, stakedVwave);
        }

        uint256 stakedEsVwave = IRewardTracker(stakedVwaveTracker)
            .depositBalances(_sender, esVwave);
        if (stakedEsVwave > 0) {
            _unstakeVwave(_sender, esVwave, stakedEsVwave, false);
            _stakeVwave(_sender, receiver, esVwave, stakedEsVwave);
        }

        uint256 stakedBnVwave = IRewardTracker(feeVwaveTracker).depositBalances(
            _sender,
            bnVwave
        );
        if (stakedBnVwave > 0) {
            IRewardTracker(feeVwaveTracker).unstakeForAccount(
                _sender,
                bnVwave,
                stakedBnVwave,
                _sender
            );
            IRewardTracker(feeVwaveTracker).stakeForAccount(
                _sender,
                receiver,
                bnVwave,
                stakedBnVwave
            );
        }

        uint256 esVwaveBalance = IERC20(esVwave).balanceOf(_sender);
        if (esVwaveBalance > 0) {
            IERC20(esVwave).transferFrom(_sender, receiver, esVwaveBalance);
        }

        uint256 vlpAmount = IRewardTracker(feeVlpTracker).depositBalances(
            _sender,
            vlp
        );
        if (vlpAmount > 0) {
            IRewardTracker(stakedVlpTracker).unstakeForAccount(
                _sender,
                feeVlpTracker,
                vlpAmount,
                _sender
            );
            IRewardTracker(feeVlpTracker).unstakeForAccount(
                _sender,
                vlp,
                vlpAmount,
                _sender
            );

            IRewardTracker(feeVlpTracker).stakeForAccount(
                _sender,
                receiver,
                vlp,
                vlpAmount
            );
            IRewardTracker(stakedVlpTracker).stakeForAccount(
                receiver,
                receiver,
                feeVlpTracker,
                vlpAmount
            );
        }

        IVester(vwaveVester).transferStakeValues(_sender, receiver);
        IVester(vlpVester).transferStakeValues(_sender, receiver);
    }

    function _compound(address _account) private {
        _compoundVwave(_account);
        _compoundVlp(_account);
    }

    function _compoundVwave(address _account) private {
        uint256 esVwaveAmount = IRewardTracker(stakedVwaveTracker)
            .claimForAccount(_account, _account);
        if (esVwaveAmount > 0) {
            _stakeVwave(_account, _account, esVwave, esVwaveAmount);
        }

        uint256 bnVwaveAmount = IRewardTracker(bonusVwaveTracker)
            .claimForAccount(_account, _account);
        if (bnVwaveAmount > 0) {
            IRewardTracker(feeVwaveTracker).stakeForAccount(
                _account,
                _account,
                bnVwave,
                bnVwaveAmount
            );
        }
    }

    function _compoundVlp(address _account) private {
        uint256 esVwaveAmount = IRewardTracker(stakedVlpTracker)
            .claimForAccount(_account, _account);
        if (esVwaveAmount > 0) {
            _stakeVwave(_account, _account, esVwave, esVwaveAmount);
        }
    }

    function _stakeVwave(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        IRewardTracker(stakedVwaveTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusVwaveTracker).stakeForAccount(
            _account,
            _account,
            stakedVwaveTracker,
            _amount
        );
        IRewardTracker(feeVwaveTracker).stakeForAccount(
            _account,
            _account,
            bonusVwaveTracker,
            _amount
        );

        emit StakeVwave(_account, _token, _amount);
    }

    function _unstakeVwave(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnVwave
    ) private {
        if (_amount == 0) {
            revert InvalidAmount();
        }

        uint256 balance = IRewardTracker(stakedVwaveTracker).stakedAmounts(
            _account
        );

        IRewardTracker(feeVwaveTracker).unstakeForAccount(
            _account,
            bonusVwaveTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusVwaveTracker).unstakeForAccount(
            _account,
            stakedVwaveTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedVwaveTracker).unstakeForAccount(
            _account,
            _token,
            _amount,
            _account
        );

        if (_shouldReduceBnVwave) {
            uint256 bnVwaveAmount = IRewardTracker(bonusVwaveTracker)
                .claimForAccount(_account, _account);
            if (bnVwaveAmount > 0) {
                IRewardTracker(feeVwaveTracker).stakeForAccount(
                    _account,
                    _account,
                    bnVwave,
                    bnVwaveAmount
                );
            }

            uint256 stakedBnVwave = IRewardTracker(feeVwaveTracker)
                .depositBalances(_account, bnVwave);
            if (stakedBnVwave > 0) {
                uint256 reductionAmount = (stakedBnVwave * _amount) / balance;
                IRewardTracker(feeVwaveTracker).unstakeForAccount(
                    _account,
                    bnVwave,
                    reductionAmount,
                    _account
                );
                IMintable(bnVwave).burn(_account, reductionAmount);
            }
        }

        emit UnstakeVwave(_account, _token, _amount);
    }

    function _validateReceiver(address _receiver) private view {
        if (
            IRewardTracker(stakedVwaveTracker).averageStakedAmounts(_receiver) >
            0 ||
            IRewardTracker(stakedVwaveTracker).cumulativeRewards(_receiver) >
            0 ||
            IRewardTracker(bonusVwaveTracker).averageStakedAmounts(_receiver) >
            0 ||
            IRewardTracker(bonusVwaveTracker).cumulativeRewards(_receiver) >
            0 ||
            IRewardTracker(feeVwaveTracker).averageStakedAmounts(_receiver) >
            0 ||
            IRewardTracker(feeVwaveTracker).cumulativeRewards(_receiver) > 0 ||
            IVester(vwaveVester).transferredAverageStakedAmounts(_receiver) >
            0 ||
            IVester(vwaveVester).transferredCumulativeRewards(_receiver) > 0 ||
            IRewardTracker(stakedVlpTracker).averageStakedAmounts(_receiver) >
            0 ||
            IRewardTracker(stakedVlpTracker).cumulativeRewards(_receiver) > 0 ||
            IRewardTracker(feeVlpTracker).averageStakedAmounts(_receiver) > 0 ||
            IRewardTracker(feeVlpTracker).cumulativeRewards(_receiver) > 0 ||
            IVester(vlpVester).transferredAverageStakedAmounts(_receiver) > 0 ||
            IVester(vlpVester).transferredCumulativeRewards(_receiver) > 0 ||
            IERC20(vwaveVester).balanceOf(_receiver) > 0 ||
            IERC20(vlpVester).balanceOf(_receiver) > 0
        ) {
            revert InvalidReceiver();
        }
    }
}
