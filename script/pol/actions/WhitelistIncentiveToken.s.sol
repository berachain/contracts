// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";

/// @notice Whitelist incentive tokens for a reward vault.
/// @dev This actions can be run only by an account with ADMIN role
contract WhitelistIncentiveTokenScript is BaseScript {
    // Placeholder. Vault where to whitelist the token.
    address internal constant REWARD_VAULT = address(0);

    // Placeholder. Incentive tokens to whitelist and corrisponding manager and incentive rate.
    address internal constant IT_X_ADDRESS = address(0);
    address internal constant IT_X_MANAGER = address(0);
    uint256 internal constant IT_X_MIN_RATE = 1e18;
    address internal constant IT_Y_ADDRESS = address(0);
    address internal constant IT_Y_MANAGER = address(0);
    uint256 internal constant IT_Y_MIN_RATE = 1e18;

    // Placeholder. Change before running the script.
    address[] internal INCENTIVE_TOKENS = [IT_X_ADDRESS, IT_Y_ADDRESS];

    // Placeholder. Change before running the script.
    address[] internal INCENTIVE_MANAGERS = [IT_X_MANAGER, IT_Y_MANAGER];

    // Placeholder. Change before running the script.
    uint256[] internal MIN_INCENTIVE_RATES = [IT_X_MIN_RATE, IT_Y_MIN_RATE];

    function run() public virtual broadcast {
        _validateCode("RewardVault", REWARD_VAULT);
        whitelistIncentiveTokens(REWARD_VAULT, INCENTIVE_TOKENS, INCENTIVE_MANAGERS, MIN_INCENTIVE_RATES);
    }

    function whitelistIncentiveToken(
        address vault,
        address token,
        address manager,
        uint256 minIncentiveRate
    )
        internal
    {
        // Reverts if the token is already whitelisted.
        RewardVault(vault).whitelistIncentiveToken(token, minIncentiveRate, manager);
        console2.log("Whitelisted incentive token %s for reward vault %s with manager %s", token, vault, manager);
        console2.log("Minimum incentive rate: %d", minIncentiveRate);
    }

    function whitelistIncentiveTokens(
        address vault,
        address[] memory tokens,
        address[] memory managers,
        uint256[] memory minIncentiveRates
    )
        internal
    {
        require(
            tokens.length == managers.length && tokens.length == minIncentiveRates.length,
            "WhitelistIncentiveTokenScript: tokens, managers and rates length must match"
        );

        for (uint256 i; i < tokens.length; ++i) {
            whitelistIncentiveToken(vault, tokens[i], managers[i], minIncentiveRates[i]);
        }
    }
}
