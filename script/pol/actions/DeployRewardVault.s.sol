// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { Storage } from "../../base/Storage.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Deploy the reward vaults for the given staking tokens
contract DeployRewardVaultScript is BaseScript, Storage, AddressBook {
    // Placeholder. Staking tokens to deploy reward vaults for.
    address internal constant LP_BERA_HONEY = address(0);
    address internal constant LP_BERA_ETH = address(0);
    address internal constant LP_BERA_WBTC = address(0);
    address internal constant LP_USDC_HONEY = address(0);
    address internal constant LP_BEE_HONEY = address(0);

    // Placeholder. Change before running the script.
    address[] internal STAKING_TOKENS = [LP_BERA_HONEY, LP_BERA_ETH, LP_BERA_WBTC, LP_USDC_HONEY, LP_BEE_HONEY];

    constructor() AddressBook(_chainType) { }

    function run() public virtual broadcast {
        _validateCode("RewardVaultFactory", _polAddresses.rewardVaultFactory);
        rewardVaultFactory = RewardVaultFactory(_polAddresses.rewardVaultFactory);
        deployRewardVaults(STAKING_TOKENS);
    }

    /// @dev Deploy the reward vault
    function deployRewardVault(address stakingToken) internal returns (address vault) {
        _validateCode("StakingToken", stakingToken);
        address predictedVaultAddress = rewardVaultFactory.predictRewardVaultAddress(stakingToken);
        vault = rewardVaultFactory.getVault(stakingToken);

        // Avoid reward vault creation reverts for collision
        if (vault == predictedVaultAddress) {
            console2.log("Rewards vault for staking token %s already exists at %s.", stakingToken, vault);
            return vault;
        }

        vault = rewardVaultFactory.createRewardVault(stakingToken);
        require(rewardVaultFactory.getVault(stakingToken) == vault, "DeployRewardVaultScript: vault creation failed");
        require(vault == predictedVaultAddress, "DeployRewardVaultScript: vault address mismatch");
        console2.log("RewardVault deployed at %s for staking token %s", address(vault), stakingToken);
    }

    function deployRewardVaults(address[] memory stakingTokens) internal {
        for (uint256 i; i < stakingTokens.length; ++i) {
            console2.log("\nDeploying RewardVault for staking token %s ...", stakingTokens[i]);
            deployRewardVault(stakingTokens[i]);
        }
    }
}
