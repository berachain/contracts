// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { BerachainGovernance } from "../../../src/gov/BerachainGovernance.sol";
import { BlockRewardController } from "../../../src/pol/rewards/BlockRewardController.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @dev Create a proposal to change POL parameters
contract ChangePOLParametersProposalScript is BaseScript, AddressBook {
    // POL - BlockRewardController params
    // The constant base rate for BGT.
    uint256 internal constant BASE_RATE = 0.5e18;
    // The reward rate for BGT.
    uint256 internal constant REWARD_RATE = 1.5e18;
    // The minimum reward rate for BGT after accounting for validator boosts.
    uint256 internal constant MIN_BOOSTED_REWARD_RATE = 0;
    // The boost mutliplier param in the function, determines the inflation cap, 18 dec.
    uint256 internal constant BOOST_MULTIPLIER = 3.5e18;
    // The reward convexity param in the function, determines how fast it converges to its max, 18 dec.
    uint256 internal constant REWARD_CONVEXITY = 0.4e18;

    string internal constant PROPOSAL_DESCRIPTION = "Update POL parameters";

    function run() public virtual broadcast {
        console2.log("Creating proposal to change POL parameters...");
        BerachainGovernance gov = BerachainGovernance(payable(_governanceAddresses.governance));

        address[] memory _targets = new address[](5);
        for (uint256 i = 0; i < _targets.length; i++) {
            _targets[i] = _polAddresses.blockRewardController;
        }

        uint256[] memory _values = new uint256[](5);
        for (uint256 i = 0; i < _values.length; i++) {
            _values[i] = 0;
        }

        bytes[] memory _calldatas = new bytes[](5);
        // set base rate
        _calldatas[0] = abi.encodeWithSelector(BlockRewardController.setBaseRate.selector, BASE_RATE, bytes(""));
        // set reward rate
        _calldatas[1] = abi.encodeWithSelector(BlockRewardController.setRewardRate.selector, REWARD_RATE, bytes(""));
        // set min boosted reward rate
        _calldatas[2] = abi.encodeWithSelector(
            BlockRewardController.setMinBoostedRewardRate.selector, MIN_BOOSTED_REWARD_RATE, bytes("")
        );
        // set boost multiplier
        _calldatas[3] =
            abi.encodeWithSelector(BlockRewardController.setBoostMultiplier.selector, BOOST_MULTIPLIER, bytes(""));
        // set reward convexity
        _calldatas[4] =
            abi.encodeWithSelector(BlockRewardController.setRewardConvexity.selector, REWARD_CONVEXITY, bytes(""));

        uint256 proposalId = gov.propose(_targets, _values, _calldatas, PROPOSAL_DESCRIPTION);
        console2.log("Proposal ID:", proposalId);
    }
}
