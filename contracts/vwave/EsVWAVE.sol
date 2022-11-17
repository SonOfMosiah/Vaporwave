// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../tokens/MintableBaseToken.sol"; // TODO

contract EsVWAVE is MintableBaseToken {
    constructor() MintableBaseToken("Escrowed VWAVE", "esVWAVE", 0) {
    }

    function id() external pure returns (string memory _name) {
        return "esVWAVE";
    }
}
