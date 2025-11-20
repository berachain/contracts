// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { BerachainGovernance } from "src/gov/BerachainGovernance.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice This script create a proposal to set the default reward allocation script
contract SetDefaultRewardAllocationScript is BaseScript, AddressBook {
    // default reward allocation vault address and weights
    // BERA-HONEY 30%
    address internal constant REWARD_VAULT_BERA_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_BERA_HONEY_WEIGHT = 3000;
    // BERA-ETH 20%
    address internal constant REWARD_VAULT_BERA_ETH = address(0);
    uint96 internal constant REWARD_VAULT_BERA_ETH_WEIGHT = 2000;
    // BERA-WBTC 20%
    address internal constant REWARD_VAULT_BERA_WBTC = address(0);
    uint96 internal constant REWARD_VAULT_BERA_WBTC_WEIGHT = 2000;
    // USDC-HONEY 10%
    address internal constant REWARD_VAULT_USDC_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_USDC_HONEY_WEIGHT = 1000;
    // BEE-HONEY 10%
    address internal constant REWARD_VAULT_BEE_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_BEE_HONEY_WEIGHT = 1000;
    // USDS-HONEY 10%
    address internal constant REWARD_VAULT_USDS_HONEY = address(0);
    uint96 internal constant REWARD_VAULT_USDS_HONEY_WEIGHT = 1000;

    address[] internal REWARD_VAULTS = [
        REWARD_VAULT_BERA_HONEY,
        REWARD_VAULT_BERA_ETH,
        REWARD_VAULT_BERA_WBTC,
        REWARD_VAULT_USDC_HONEY,
        REWARD_VAULT_BEE_HONEY,
        REWARD_VAULT_USDS_HONEY
    ];

    uint96[] internal REWARD_VAULT_WEIGHTS = [
        REWARD_VAULT_BERA_HONEY_WEIGHT,
        REWARD_VAULT_BERA_ETH_WEIGHT,
        REWARD_VAULT_BERA_WBTC_WEIGHT,
        REWARD_VAULT_USDC_HONEY_WEIGHT,
        REWARD_VAULT_BEE_HONEY_WEIGHT,
        REWARD_VAULT_USDS_HONEY_WEIGHT
    ];

    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        _validateCode("Governance", _governanceAddresses.governance);
        _validateCode("BeraChef", _polAddresses.beraChef);
        _validateCode("BGT", _polAddresses.bgt);
        _validateVaultAddresses();

        require(
            REWARD_VAULTS.length == REWARD_VAULT_WEIGHTS.length,
            "SetDefaultRewardAllocationScript: vaults and weights length must match"
        );

        BerachainGovernance governance = BerachainGovernance(payable(_governanceAddresses.governance));
        uint256 proposalThreshold = governance.proposalThreshold();
        require(
            IERC20(_polAddresses.bgt).balanceOf(msg.sender) >= proposalThreshold,
            "SetDefaultRewardAllocationScript: insufficient BGT balance"
        );

        address[] memory targets = new address[](1);
        targets[0] = _polAddresses.beraChef;

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](6);
        for (uint8 i = 0; i < REWARD_VAULT_WEIGHTS.length; i++) {
            weights[i] = IBeraChef.Weight({ receiver: REWARD_VAULTS[i], percentageNumerator: REWARD_VAULT_WEIGHTS[i] });
        }

        IBeraChef.RewardAllocation memory rewardAllocations =
            IBeraChef.RewardAllocation({ startBlock: 0, weights: weights });

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IBeraChef.setDefaultRewardAllocation, (rewardAllocations));

        string memory description =
            string(abi.encodePacked("Set default reward allocation to ", REWARD_VAULTS.length, " vaults"));

        console2.log("Creating proposal to set default reward allocation...");
        uint256 proposalId = governance.propose(targets, new uint256[](1), calldatas, description);
        console2.log("Proposal ID: %d", proposalId);
    }

    function _validateVaultAddresses() internal view {
        _validateCode("REWARD_VAULT_BERA_HONEY", REWARD_VAULT_BERA_HONEY);
        _validateCode("REWARD_VAULT_BERA_ETH", REWARD_VAULT_BERA_ETH);
        _validateCode("REWARD_VAULT_BERA_WBTC", REWARD_VAULT_BERA_WBTC);
        _validateCode("REWARD_VAULT_USDC_HONEY", REWARD_VAULT_USDC_HONEY);
        _validateCode("REWARD_VAULT_BEE_HONEY", REWARD_VAULT_BEE_HONEY);
        _validateCode("REWARD_VAULT_USDS_HONEY", REWARD_VAULT_USDS_HONEY);
    }
}
