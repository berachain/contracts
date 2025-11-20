// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { BeraChef } from "./rewards/BeraChef.sol";
import { RewardVault } from "./rewards/RewardVault.sol";
import { RewardVaultFactory } from "./rewards/RewardVaultFactory.sol";
import { BlockRewardController } from "./rewards/BlockRewardController.sol";
import { Distributor } from "./rewards/Distributor.sol";

/// @title POLDeployer
/// @author Berachain Team
/// @notice The POLDeployer contract is responsible for deploying the PoL contracts.
contract POLDeployer is Create2Deployer {
    uint8 internal constant maxNumWeightsPerRewardAllocation = 10;

    /// @dev Generalized Index of the pubkey of the first validator (validator index of 0) in the registry of the
    /// beacon state in the beacon block on the Electra beacon fork on Berachain.
    uint64 internal constant ZERO_VALIDATOR_PUBKEY_G_INDEX = 6_350_779_162_034_176;

    /// @dev Generalized Index of the proposer index in the beacon block on both the Deneb and Electra beacon forks
    /// on Berachain.
    uint64 internal constant PROPOSER_INDEX_G_INDEX = 9;

    /// @notice The address of the BeaconDeposit contract.
    /// @dev This is a placeholder address. defined here instead of constructor to avoid stack too deep error.
    address internal constant BEACON_DEPOSIT = 0x4242424242424242424242424242424242424242;

    /// @notice The BeraChef contract.
    // solhint-disable-next-line immutable-vars-naming
    BeraChef public immutable beraChef;

    /// @notice The BlockRewardController contract.
    // solhint-disable-next-line immutable-vars-naming
    BlockRewardController public immutable blockRewardController;

    /// @notice The RewardVaultFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    RewardVaultFactory public immutable rewardVaultFactory;

    /// @notice The Distributor contract.
    // solhint-disable-next-line immutable-vars-naming
    Distributor public immutable distributor;

    constructor(
        address bgt,
        address governance,
        Salt memory beraChefSalt,
        Salt memory blockRewardControllerSalt,
        Salt memory distributorSalt,
        Salt memory rewardVaultFactorySalt,
        uint256 rewardVaultSalt
    ) {
        // deploy the BeraChef implementation
        address beraChefImpl = deployWithCreate2(beraChefSalt.implementation, type(BeraChef).creationCode);
        // deploy the BeraChef proxy
        beraChef = BeraChef(deployProxyWithCreate2(beraChefImpl, beraChefSalt.proxy));

        // deploy the BlockRewardController implementation
        address blockRewardControllerImpl =
            deployWithCreate2(blockRewardControllerSalt.implementation, type(BlockRewardController).creationCode);
        // deploy the BlockRewardController proxy
        blockRewardController =
            BlockRewardController(deployProxyWithCreate2(blockRewardControllerImpl, blockRewardControllerSalt.proxy));

        // deploy the Distributor implementation
        address distributorImpl = deployWithCreate2(distributorSalt.implementation, type(Distributor).creationCode);
        // deploy the Distributor proxy
        distributor = Distributor(deployProxyWithCreate2(distributorImpl, distributorSalt.proxy));

        // deploy the RewardVault implementation
        address vaultImpl = deployWithCreate2(rewardVaultSalt, type(RewardVault).creationCode);
        address rewardVaultFactoryImpl =
            deployWithCreate2(rewardVaultFactorySalt.implementation, type(RewardVaultFactory).creationCode);
        // deploy the RewardVaultFactory proxy
        rewardVaultFactory =
            RewardVaultFactory(deployProxyWithCreate2(rewardVaultFactoryImpl, rewardVaultFactorySalt.proxy));

        // initialize the contracts
        beraChef.initialize(
            address(distributor),
            address(rewardVaultFactory),
            governance,
            BEACON_DEPOSIT,
            maxNumWeightsPerRewardAllocation
        );
        blockRewardController.initialize(bgt, address(distributor), BEACON_DEPOSIT, governance);
        distributor.initialize(
            address(beraChef),
            bgt,
            address(blockRewardController),
            governance,
            ZERO_VALIDATOR_PUBKEY_G_INDEX,
            PROPOSER_INDEX_G_INDEX
        );
        rewardVaultFactory.initialize(bgt, address(distributor), BEACON_DEPOSIT, governance, vaultImpl);
    }
}
