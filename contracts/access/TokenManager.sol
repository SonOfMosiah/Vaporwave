//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../peripherals/interfaces/ITimelock.sol";

/// User does not have function permissions
error Forbidden();
/// Contract is already initialized
error AlreadyInitialized();
/// Action has already been signed
error AlreadySigned();
/// Action has not been signalled
error ActionNotSignalled();
/// Action does not have sufficient authorization
error ActionNotAuthorized();

/// @title Vaporwave Token Manager
contract TokenManager is ReentrancyGuard {
    /// True if the contract has been initialized
    bool public isInitialized;

    /// The current action nonce
    /// @dev Increments for every action
    uint256 public actionsNonce;
    /// Minimum authorizations required for an action
    uint256 public minAuthorizations;

    /// Contract admin
    address public admin;

    /// Array of valid signers
    address[] public signers;
    /// Mapping of valid signers
    mapping(address => bool) public isSigner;
    /// Mapping of pending actions
    mapping(bytes32 => bool) public pendingActions;
    /// Mapping of addresses to their signed actions
    mapping(address => mapping(bytes32 => bool)) public signedActions;

    /// @notice Emitted when an approve action is signalled
    /// @param token The address of the token contract
    /// @param spender The address of the spender
    /// @param amount The amount to approve
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignalApprove(
        address token,
        address spender,
        uint256 amount,
        bytes32 action,
        uint256 nonce
    );
    /// @notice Emitted when an approveNFT action is signalled
    /// @param token The address of the token contract
    /// @param spender The address of the spender
    /// @param tokenId The tokenId to approve
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignalApproveNFT(
        address token,
        address spender,
        uint256 tokenId,
        bytes32 action,
        uint256 nonce
    );
    /// @notice Emitted when an approveNFTs action is signalled
    /// @param token The address of the token contract
    /// @param spender The address of the spender
    /// @param tokenIds An array of tokenIds to approve
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignalApproveNFTs(
        address token,
        address spender,
        uint256[] tokenIds,
        bytes32 action,
        uint256 nonce
    );
    /// @notice Emitted when a setAdmin action is signalled
    /// @param target The address of target contract
    /// @param admin The address of the new admin
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignalSetAdmin(
        address target,
        address admin,
        bytes32 action,
        uint256 nonce
    );
    /// @notice Emitted when a signalSetOwner action is signalled
    /// @param timelock The address of timelock contract
    /// @param target The address of target contract
    /// @param owner The address of the new owner
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignalSetOwner(
        address timelock,
        address target,
        address owner,
        bytes32 action,
        uint256 nonce
    );
    /// @notice Emitted when an action is set as pending
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignalPendingAction(bytes32 action, uint256 nonce);
    /// @notice Emitted when an action is signed
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event SignAction(bytes32 action, uint256 nonce);
    /// @notice Emitted when an action is cleared
    /// @param action The hash of the action (bytes32)
    /// @param nonce The nonce of the action
    event ClearAction(bytes32 action, uint256 nonce);

    /// Modified functions can only be called by the admin
    modifier onlyAdmin() {
        if (msg.sender != admin) {
            revert Forbidden();
        }
        _;
    }

    /// Modified functions can only be called by a signer
    modifier onlySigner() {
        if (!isSigner[msg.sender]) {
            revert Forbidden();
        }
        _;
    }

    constructor(uint256 _minAuthorizations) {
        admin = msg.sender;
        minAuthorizations = _minAuthorizations;
    }

    /// @notice Signal a token approve action
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _amount The amount to approve
    function signalApprove(
        address _token,
        address _spender,
        uint256 _amount
    ) external nonReentrant onlyAdmin {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount, nonce)
        );
        _setPendingAction(action, nonce);
        emit SignalApprove(_token, _spender, _amount, action, nonce);
    }

    /// @notice Sign a token approve action
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _amount The amount to approve
    /// @param _nonce The nonce of the action
    function signApprove(
        address _token,
        address _spender,
        uint256 _amount,
        uint256 _nonce
    ) external nonReentrant onlySigner {
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount, _nonce)
        );
        _validateAction(action);
        if (signedActions[msg.sender][action]) {
            revert AlreadySigned();
        }
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    /// @notice Call a token approve action
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _amount The amount to approve
    /// @param _nonce The nonce of the action
    function approve(
        address _token,
        address _spender,
        uint256 _amount,
        uint256 _nonce
    ) external nonReentrant onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approve", _token, _spender, _amount, _nonce)
        );
        _validateAction(action);
        _validateAuthorization(action);

        IERC20(_token).approve(_spender, _amount);
        _clearAction(action, _nonce);
    }

    /// @notice Signal an NFT approve action
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _tokenId The tokenId to approve
    function signalApproveNFT(
        address _token,
        address _spender,
        uint256 _tokenId
    ) external nonReentrant onlyAdmin {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(
            abi.encodePacked("approveNFT", _token, _spender, _tokenId, nonce)
        );
        _setPendingAction(action, nonce);
        emit SignalApproveNFT(_token, _spender, _tokenId, action, nonce);
    }

    /// @notice Sign an NFT approve action
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _tokenId The tokenId to approve
    /// @param _nonce The nonce of the action
    function signApproveNFT(
        address _token,
        address _spender,
        uint256 _tokenId,
        uint256 _nonce
    ) external nonReentrant onlySigner {
        bytes32 action = keccak256(
            abi.encodePacked("approveNFT", _token, _spender, _tokenId, _nonce)
        );
        _validateAction(action);
        if (signedActions[msg.sender][action]) {
            revert AlreadySigned();
        }
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    /// @notice Call an NFT approve action
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _tokenId The tokenId to approve
    /// @param _nonce The nonce of the action
    function approveNFT(
        address _token,
        address _spender,
        uint256 _tokenId,
        uint256 _nonce
    ) external nonReentrant onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approveNFT", _token, _spender, _tokenId, _nonce)
        );
        _validateAction(action);
        _validateAuthorization(action);

        IERC721(_token).approve(_spender, _tokenId);
        _clearAction(action, _nonce);
    }

    /// @notice Signal an NFT approve action for an array of tokenIds
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _tokenIds An array of tokenIds to approve
    function signalApproveNFTs(
        address _token,
        address _spender,
        uint256[] memory _tokenIds
    ) external nonReentrant onlyAdmin {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(
            abi.encodePacked("approveNFTs", _token, _spender, _tokenIds, nonce)
        );
        _setPendingAction(action, nonce);
        emit SignalApproveNFTs(_token, _spender, _tokenIds, action, nonce);
    }

    /// @notice Sign an NFT approve action for an array of tokenIds
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _tokenIds An array of tokenIds to approve
    /// @param _nonce The nonce of the action
    function signApproveNFTs(
        address _token,
        address _spender,
        uint256[] memory _tokenIds,
        uint256 _nonce
    ) external nonReentrant onlySigner {
        bytes32 action = keccak256(
            abi.encodePacked("approveNFTs", _token, _spender, _tokenIds, _nonce)
        );
        _validateAction(action);
        if (signedActions[msg.sender][action]) {
            revert AlreadySigned();
        }
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    /// @notice Call an NFT approve action for an array of tokenIds
    /// @param _token The address of the token contract
    /// @param _spender The address of the spender
    /// @param _tokenIds An array of tokenIds to approve
    /// @param _nonce The nonce of the action
    function approveNFTs(
        address _token,
        address _spender,
        uint256[] memory _tokenIds,
        uint256 _nonce
    ) external nonReentrant onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked("approveNFTs", _token, _spender, _tokenIds, _nonce)
        );
        _validateAction(action);
        _validateAuthorization(action);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            IERC721(_token).approve(_spender, _tokenIds[i]);
        }
        _clearAction(action, _nonce);
    }

    /// @notice Transfer an array of NFTs to this contract
    /// @dev The NFTs must be approved by the spender first
    /// @param _token The address of the NFT contract
    /// @param _sender The address to send the NFTs from
    /// @param _tokenIds The array of tokenIds to transfer
    function receiveNFTs(
        address _token,
        address _sender,
        uint256[] memory _tokenIds
    ) external nonReentrant onlyAdmin {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            IERC721(_token).transferFrom(_sender, address(this), _tokenIds[i]);
        }
    }

    /// @notice Signal a setAdmin action
    /// @param _target The address of the target contract
    /// @param _admin The address of the new admin
    function signalSetAdmin(address _target, address _admin)
        external
        nonReentrant
        onlySigner
    {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(
            abi.encodePacked("setAdmin", _target, _admin, nonce)
        );
        _setPendingAction(action, nonce);
        signedActions[msg.sender][action] = true;
        emit SignalSetAdmin(_target, _admin, action, nonce);
    }

    /// @notice Sign a setAdmin action
    /// @param _target The address of the target contract
    /// @param _admin The address of the new admin
    /// @param _nonce The nonce of the action
    function signSetAdmin(
        address _target,
        address _admin,
        uint256 _nonce
    ) external nonReentrant onlySigner {
        bytes32 action = keccak256(
            abi.encodePacked("setAdmin", _target, _admin, _nonce)
        );
        _validateAction(action);
        if (signedActions[msg.sender][action]) {
            revert AlreadySigned();
        }
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    /// @notice Call a setAdmin action
    /// @param _target The address of the target contract
    /// @param _admin The address of the new admin
    /// @param _nonce The nonce of the action
    function setAdmin(
        address _target,
        address _admin,
        uint256 _nonce
    ) external nonReentrant onlySigner {
        bytes32 action = keccak256(
            abi.encodePacked("setAdmin", _target, _admin, _nonce)
        );
        _validateAction(action);
        _validateAuthorization(action);

        ITimelock(_target).setAdmin(_admin);
        _clearAction(action, _nonce);
    }

    /// @notice Signal a setOwner action
    /// @param _timelock The address of the timelock contract
    /// @param _target The address of the target contract
    /// @param _owner The address of the new owner
    function signalSetOwner(
        address _timelock,
        address _target,
        address _owner
    ) external nonReentrant onlyAdmin {
        actionsNonce++;
        uint256 nonce = actionsNonce;
        bytes32 action = keccak256(
            abi.encodePacked(
                "signalSetOwner",
                _timelock,
                _target,
                _owner,
                nonce
            )
        );
        _setPendingAction(action, nonce);
        signedActions[msg.sender][action] = true;
        emit SignalSetOwner(_timelock, _target, _owner, action, nonce);
    }

    /// @notice Sign a setOwner action
    /// @param _timelock The address of the timelock contract
    /// @param _target The address of the target contract
    /// @param _owner The address of the new owner
    /// @param _nonce The nonce of the action
    function signSetOwner(
        address _timelock,
        address _target,
        address _owner,
        uint256 _nonce
    ) external nonReentrant onlySigner {
        bytes32 action = keccak256(
            abi.encodePacked(
                "signalSetOwner",
                _timelock,
                _target,
                _owner,
                _nonce
            )
        );
        _validateAction(action);
        if (signedActions[msg.sender][action]) {
            revert AlreadySigned();
        }
        signedActions[msg.sender][action] = true;
        emit SignAction(action, _nonce);
    }

    /// @notice Call a setOwner action
    /// @param _timelock The address of the timelock contract
    /// @param _target The address of the target contract
    /// @param _owner The address of the new owner
    /// @param _nonce The nonce of the action
    function setOwner(
        address _timelock,
        address _target,
        address _owner,
        uint256 _nonce
    ) external nonReentrant onlyAdmin {
        bytes32 action = keccak256(
            abi.encodePacked(
                "signalSetOwner",
                _timelock,
                _target,
                _owner,
                _nonce
            )
        );
        _validateAction(action);
        _validateAuthorization(action);

        ITimelock(_timelock).signalSetOwner(_target, _owner);
        _clearAction(action, _nonce);
    }

    /// @notice Initialize the contract
    /// @param _signers An array of addresses that are valid signers
    function initialize(address[] memory _signers) public virtual onlyAdmin {
        // Question: should this be external?
        if (isInitialized) {
            revert AlreadyInitialized();
        }
        isInitialized = true;

        signers = _signers;
        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }
    }

    /// @notice Get the lengths of the signers array
    /// @return The length of the signers array
    function signersLength() public view returns (uint256) {
        return signers.length;
    }

    function _setPendingAction(bytes32 _action, uint256 _nonce) private {
        pendingActions[_action] = true;
        emit SignalPendingAction(_action, _nonce);
    }

    function _clearAction(bytes32 _action, uint256 _nonce) private {
        if (!pendingActions[_action]) {
            revert ActionNotSignalled();
        }
        delete pendingActions[_action];
        emit ClearAction(_action, _nonce);
    }

    function _validateAction(bytes32 _action) private view {
        if (!pendingActions[_action]) {
            revert ActionNotSignalled();
        }
    }

    function _validateAuthorization(bytes32 _action) private view {
        uint256 count = 0;
        for (uint256 i = 0; i < signers.length; i++) {
            address signer = signers[i];
            if (signedActions[signer][_action]) {
                count++;
            }
        }

        if (count == 0 || count < minAuthorizations) {
            revert ActionNotAuthorized();
        }
    }
}
