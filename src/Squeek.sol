// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Squeek
/// @notice A fixed supply of one billion SQK, with 18 decimals and ordinary ERC-20 transfers.
/// @dev The immediate deployer receives the entire supply. No administrative powers are exposed.
contract Squeek is ERC20 {
    /// @notice The lifetime supply in the token's smallest units (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Squeek", "SQK") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
