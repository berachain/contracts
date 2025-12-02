// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BasePredictScript, console2 } from "../base/BasePredict.s.sol";
import { BGT } from "src/pol/BGT.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";
import { RewardAllocatorFactory } from "src/pol/rewards/RewardAllocatorFactory.sol";
import { AddressBook } from "../base/AddressBook.sol";

contract POLPredictAddressesScript is BasePredictScript, AddressBook {
    constructor() AddressBook(_chainType) { }

    function run() public view {
        console2.log("POL Contracts will be deployed at: ");
        _predictAddress("BGT", type(BGT).creationCode);
        _predictProxyAddress("BeraChef", type(BeraChef).creationCode);
        _predictAddress("BeraChef Impl", type(BeraChef).creationCode);
        _predictProxyAddress("BlockRewardController", type(BlockRewardController).creationCode);
        _predictAddress("BlockRewardController Impl", type(BlockRewardController).creationCode);
        _predictProxyAddress("Distributor", type(Distributor).creationCode);
        _predictAddress("Distributor Impl", type(Distributor).creationCode);
        _predictProxyAddress("RewardVaultFactory", type(RewardVaultFactory).creationCode);
        _predictAddress("RewardVaultFactory Impl", type(RewardVaultFactory).creationCode);
        _predictAddress("RewardVault Impl", type(RewardVault).creationCode);
        _predictProxyAddress("BGTStaker", type(BGTStaker).creationCode);
        _predictAddress("BGTStaker Impl", type(BGTStaker).creationCode);
        _predictProxyAddress("FeeCollector", type(FeeCollector).creationCode);
        _predictAddress("FeeCollector Impl", type(FeeCollector).creationCode);
        _predictProxyAddress("BGTIncentiveDistributor", type(BGTIncentiveDistributor).creationCode);
        _predictAddress("BGTIncentiveDistributor Impl", type(BGTIncentiveDistributor).creationCode);
        _predictProxyAddress("BGT Incentive Fee Collector", type(BGTIncentiveFeeCollector).creationCode);
        _predictAddress("BGT Incentive Fee Collector Impl", type(BGTIncentiveFeeCollector).creationCode);
        _predictProxyAddress("WBERA Staker Vault", type(WBERAStakerVault).creationCode);
        _predictAddress("WBERA Staker Vault Impl", type(WBERAStakerVault).creationCode);
        _predictProxyAddress(
            "WBERA Staker Vault Withdrawal Request", type(WBERAStakerVaultWithdrawalRequest).creationCode
        );
        _predictAddress(
            "WBERA Staker Vault Withdrawal Request Impl", type(WBERAStakerVaultWithdrawalRequest).creationCode
        );
        _predictProxyAddress("RewardVaultHelper", type(RewardVaultHelper).creationCode);
        _predictAddress("RewardVaultHelper Impl", type(RewardVaultHelper).creationCode);
        _predictProxyAddress("RewardAllocatorFactory", type(RewardAllocatorFactory).creationCode);
        _predictAddress("RewardAllocatorFactory Impl", type(RewardAllocatorFactory).creationCode);
    }
}
