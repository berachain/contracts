// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { Storage } from "../../base/Storage.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Whitelist given reward vaults
/// @dev This actions can be run only by an account with ADMIN role
contract WhitelistRewardVaultScript is BaseScript, Storage, AddressBook {
    // Placeholder. Reward vault addresses to whitelist and metadata.
    // METADATAs are used from indexer to save and then display the vault's informations.
    // TDB: Format of METADATA (can be empty string)
    address internal constant REWARD_VAULT_BERA_HONEY = address(0);
    string internal constant REWARD_VAULT_BERA_HONEY_METADATA = "BERA-HONEY";
    address internal constant REWARD_VAULT_BERA_ETH = address(0);
    string internal constant REWARD_VAULT_BERA_ETH_METADATA = "BERA-ETH";
    address internal constant REWARD_VAULT_BERA_WBTC = address(0);
    string internal constant REWARD_VAULT_BERA_WBTC_METADATA = "BERA-WBTC";
    address internal constant REWARD_VAULT_USDC_HONEY = address(0);
    string internal constant REWARD_VAULT_USDC_HONEY_METADATA = "USDC-HONEY";
    address internal constant REWARD_VAULT_BEE_HONEY = address(0);
    string internal constant REWARD_VAULT_BEE_HONEY_METADATA = "BEE-HONEY";
    address internal constant REWARD_VAULT_USDS_HONEY = address(0);
    string internal constant REWARD_VAULT_USDS_HONEY_METADATA = "USDS-HONEY";

    address[] internal REWARD_VAULTS = [
        REWARD_VAULT_BERA_HONEY,
        REWARD_VAULT_BERA_ETH,
        REWARD_VAULT_BERA_WBTC,
        REWARD_VAULT_USDC_HONEY,
        REWARD_VAULT_BEE_HONEY,
        REWARD_VAULT_USDS_HONEY
    ];

    string[] internal REWARD_VAULTS_METADATA = [
        REWARD_VAULT_BERA_HONEY_METADATA,
        REWARD_VAULT_BERA_ETH_METADATA,
        REWARD_VAULT_BERA_WBTC_METADATA,
        REWARD_VAULT_USDC_HONEY_METADATA,
        REWARD_VAULT_BEE_HONEY_METADATA,
        REWARD_VAULT_USDS_HONEY_METADATA
    ];

    constructor() AddressBook(_chainType) { }

    function run() public virtual broadcast {
        _validateCode("BeraChef", _polAddresses.beraChef);
        beraChef = BeraChef(_polAddresses.beraChef);

        whitelistRewardVaults(REWARD_VAULTS, REWARD_VAULTS_METADATA);
    }

    /// @dev Whitelist the reward vault
    function whitelistRewardVault(address vault, string memory metadata) internal {
        _validateCode("RewardVault", vault);
        if (beraChef.isWhitelistedVault(vault)) {
            console2.log("Rewards Vault %s is already whitelisted", vault);
            return;
        }
        beraChef.setVaultWhitelistedStatus(vault, true, metadata);
        require(beraChef.isWhitelistedVault(vault), "WhitelistVaultScript: failed to whitelist vault");
        console2.log("Whitelisted Vault %s. Metadata: %s", vault, metadata);
    }

    function whitelistRewardVaults(address[] memory vaults, string[] memory metadata) internal {
        require(vaults.length == metadata.length, "WhitelistVaultScript: invalid arrays length");
        for (uint256 i; i < vaults.length; ++i) {
            whitelistRewardVault(vaults[i], metadata[i]);
        }
    }
}
