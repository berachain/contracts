// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { Storage } from "../../base/Storage.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { IRewardAllocation } from "src/pol/interfaces/IRewardAllocation.sol";

/// @notice Set default reward allocation.
/// @dev This actions can be run only by an account with ADMIN role.
contract WhitelistIncentiveTokenScript is BaseScript, Storage, AddressBook {
    // Placeholder. Default reward allocation vault addresses and weights.
    // BERA-HONEY 35%
    address internal constant REWARD_VAULT_BERA_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_BERA_HONEY_WEIGHT = 3500;
    // BERA-ETH 25%
    address internal constant REWARD_VAULT_BERA_ETH = address(0);
    uint96 internal constant REWARD_VAULT_BERA_ETH_WEIGHT = 2500;
    // BERA-WBTC 25%
    address internal constant REWARD_VAULT_BERA_WBTC = address(0);
    uint96 internal constant REWARD_VAULT_BERA_WBTC_WEIGHT = 2500;
    // USDC-HONEY 7.5%
    address internal constant REWARD_VAULT_USDC_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_USDC_HONEY_WEIGHT = 750;
    // BEE-HONEY 7.5%
    address internal constant REWARD_VAULT_BEE_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_BEE_HONEY_WEIGHT = 750;

    // Placeholder. Change before running the script.
    address[] internal REWARD_VAULTS = [
        REWARD_VAULT_BERA_HONEY,
        REWARD_VAULT_BERA_ETH,
        REWARD_VAULT_BERA_WBTC,
        REWARD_VAULT_USDC_HONEY,
        REWARD_VAULT_BEE_HONEY
    ];

    // Placeholder. Change before running the script.
    uint96[] internal REWARD_VAULT_WEIGHTS = [
        REWARD_VAULT_BERA_HONEY_WEIGHT,
        REWARD_VAULT_BERA_ETH_WEIGHT,
        REWARD_VAULT_BERA_WBTC_WEIGHT,
        REWARD_VAULT_USDC_HONEY_WEIGHT,
        REWARD_VAULT_BEE_HONEY_WEIGHT
    ];

    function run() public virtual broadcast {
        _validateCode("BeraChef", _polAddresses.beraChef);
        beraChef = BeraChef(_polAddresses.beraChef);

        setDefaultRewardAllocation(REWARD_VAULTS, REWARD_VAULT_WEIGHTS);
    }

    function setDefaultRewardAllocation(address[] memory vaults, uint96[] memory vaultWeights) internal {
        require(
            vaults.length == vaultWeights.length,
            "SetDefaultRewardAllocationScript: vaults and weights length must match"
        );

        // Create the weight struct array
        IRewardAllocation.Weight[] memory weights = new IRewardAllocation.Weight[](vaults.length);
        for (uint8 i = 0; i < vaults.length; i++) {
            _validateCode("RewardVault", vaults[i]);
            weights[i] = IRewardAllocation.Weight({ receiver: vaults[i], percentageNumerator: vaultWeights[i] });
        }

        // Create the reward allocation struct
        IRewardAllocation.RewardAllocation memory rewardAllocations =
            IRewardAllocation.RewardAllocation({ startBlock: 0, weights: weights });

        // BeraChef validate vaults and weights
        beraChef.setDefaultRewardAllocation(rewardAllocations);
        console2.log("Default reward allocation set");
    }
}
