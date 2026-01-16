// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";
import { BeraChef, IBeraChef } from "src/pol/rewards/BeraChef.sol";
import { BGT } from "src/pol/BGT.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { BGTFeeDeployer } from "src/pol/BGTFeeDeployer.sol";
import { POLDeployer } from "src/pol/POLDeployer.sol";
import { WBERA } from "src/WBERA.sol";
import { BeaconDeposit } from "src/pol/BeaconDeposit.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";

abstract contract Storage {
    BGT internal bgt;
    BeaconDeposit internal beaconDeposit;
    BeraChef internal beraChef;
    BGTStaker internal bgtStaker;
    BlockRewardController internal blockRewardController;
    RewardVaultFactory internal rewardVaultFactory;
    RewardVault internal rewardVault;
    FeeCollector internal feeCollector;
    Distributor internal distributor;
    POLDeployer internal polDeployer;
    BGTFeeDeployer internal feeDeployer;
    WBERA internal wbera;
    Honey internal honey;
    HoneyFactory internal honeyFactory;
    HoneyFactoryReader internal honeyFactoryReader;
    BGTIncentiveDistributor internal bgtIncentiveDistributor;
    WBERAStakerVault internal wberaStakerVault;
    WBERAStakerVaultWithdrawalRequest internal wberaStakerVaultWithdrawalRequest;
    BGTIncentiveFeeCollector internal bgtIncentiveFeeCollector;
    LSTStakerVaultFactory internal lstStakerVaultFactory;
    LSTStakerVault internal lstStakerVault;
    LSTStakerVaultWithdrawalRequest internal lstStakerVaultWithdrawalRequest;
}
