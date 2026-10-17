// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title EARLY TEST (EARLY)
/// @notice Fixed-supply ERC-20 with a public link to its Telegram community.
/// @dev The constructor mints the entire supply to its caller (the factory at launch).
/// There are no administrative roles or external mint/burn entry points.
contract EarlyToken is ERC20 {
    /// @notice One billion tokens expressed in 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Community link; this is metadata, not an onchain Telegram integration.
    string public constant TELEGRAM_URL = "https://t.me/EARLYCATODAY";

    constructor() ERC20("EARLY TEST", "EARLY") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

