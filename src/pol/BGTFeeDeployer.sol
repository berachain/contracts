// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Salt } from "../base/Salt.sol";
import { BGTStaker } from "./BGTStaker.sol";
import { FeeCollector } from "./FeeCollector.sol";

/// @title BGTFeeDeployer
/// @author Berachain Team
/// @notice The BGTFeeDeployer contract is responsible for deploying the BGTStaker and FeeCollector contracts.
contract BGTFeeDeployer is Create2Deployer {
    /// @notice The BGTStaker contract.
    // solhint-disable-next-line immutable-vars-naming
    BGTStaker public immutable bgtStaker;

    /// @notice The FeeCollector contract.
    // solhint-disable-next-line immutable-vars-naming
    FeeCollector public immutable feeCollector;

    constructor(
        address bgt,
        address governance,
        address rewardToken,
        Salt memory bgtStakerSalt,
        Salt memory feeCollectorSalt,
        uint256 payoutAmount
    ) {
        // deploy the BGTStaker implementation
        address bgtStakerImpl = deployWithCreate2(bgtStakerSalt.implementation, type(BGTStaker).creationCode);
        // deploy the BGTStaker proxy
        bgtStaker = BGTStaker(deployProxyWithCreate2(bgtStakerImpl, bgtStakerSalt.proxy));

        // deploy the FeeCollector implementation
        address feeCollectorImpl = deployWithCreate2(feeCollectorSalt.implementation, type(FeeCollector).creationCode);
        // deploy the FeeCollector proxy
        feeCollector = FeeCollector(deployProxyWithCreate2(feeCollectorImpl, feeCollectorSalt.proxy));

        // initialize the contracts
        bgtStaker.initialize(bgt, address(feeCollector), governance, rewardToken);
        feeCollector.initialize(governance, rewardToken, address(bgtStaker), payoutAmount);
    }
}
