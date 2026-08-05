// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BUSD } from "src/busd/BUSD.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";
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
import { IncentivesCollector } from "src/pol/IncentivesCollector.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";
import { DedicatedEmissionStreamManager } from "src/pol/rewards/DedicatedEmissionStreamManager.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";

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
    BUSD internal busd;
    BUSDFactory internal busdFactory;
    BUSDFactoryReader internal busdFactoryReader;
    BGTIncentiveDistributor internal bgtIncentiveDistributor;
    WBERAStakerVault internal wberaStakerVault;
    WBERAStakerVaultWithdrawalRequest internal wberaStakerVaultWithdrawalRequest;
    IncentivesCollector internal incentivesCollector;
    LSTStakerVaultFactory internal lstStakerVaultFactory;
    LSTStakerVault internal lstStakerVault;
    LSTStakerVaultWithdrawalRequest internal lstStakerVaultWithdrawalRequest;
    DedicatedEmissionStreamManager internal dedicatedEmissionStreamManager;
    RewardVaultHelper internal rewardVaultHelper;
}
