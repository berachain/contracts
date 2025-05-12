// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript, console2 } from "../base/BasePredict.s.sol";
import { WBERA } from "src/WBERA.sol";
import { BGT } from "src/pol/BGT.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import {
    WBERA_SALT,
    BGT_SALT,
    BERA_CHEF_SALT,
    BLOCK_REWARD_CONTROLLER_SALT,
    DISTRIBUTOR_SALT,
    REWARDS_FACTORY_SALT,
    BGT_STAKER_SALT,
    FEE_COLLECTOR_SALT,
    BGT_INCENTIVE_DISTRIBUTOR_SALT
} from "./POLSalts.sol";

contract POLPredictAddressesScript is BasePredictScript {
    function run() public pure {
        console2.log("POL Contracts will be deployed at: ");
        // TODO: Review implementation's salts
        _predictAddress("BGT", type(BGT).creationCode, BGT_SALT);
        _predictProxyAddress("BeraChef", type(BeraChef).creationCode, 0, BERA_CHEF_SALT);
        _predictAddress("BeraChef Impl", type(BeraChef).creationCode, 0);
        _predictProxyAddress(
            "BlockRewardController", type(BlockRewardController).creationCode, 0, BLOCK_REWARD_CONTROLLER_SALT
        );
        _predictProxyAddress("Distributor", type(Distributor).creationCode, 0, DISTRIBUTOR_SALT);
        _predictProxyAddress("RewardVaultFactory", type(RewardVaultFactory).creationCode, 0, REWARDS_FACTORY_SALT);
        _predictAddress("RewardVault Impl", type(RewardVault).creationCode, 0);
        _predictProxyAddress("BGTStaker", type(BGTStaker).creationCode, 0, BGT_STAKER_SALT);
        _predictProxyAddress("FeeCollector", type(FeeCollector).creationCode, 0, FEE_COLLECTOR_SALT);
        _predictProxyAddress(
            "BGTIncentiveDistributor", type(BGTIncentiveDistributor).creationCode, 0, BGT_INCENTIVE_DISTRIBUTOR_SALT
        );
    }
}
