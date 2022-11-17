// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVwaveTimelock {
    function setAdmin(address _admin) external;
    function setIsLeverageEnabled(address _vault, bool _isLeverageEnabled) external;
    function signalSetGov(address _target, address _gov) external;
}
