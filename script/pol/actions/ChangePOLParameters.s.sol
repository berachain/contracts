// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { BaseScript } from "../../base/Base.s.sol";
import { BlockRewardController } from "../../../src/pol/rewards/BlockRewardController.sol";
import { ConfigPOL } from "../logic/ConfigPOL.sol";
import { Storage } from "../../base/Storage.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @dev Sender must have permission to update parameters.
contract ChangePOLParametersScript is BaseScript, Storage, ConfigPOL, AddressBook {
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

    function run() public virtual broadcast {
        blockRewardController = BlockRewardController(_polAddresses.blockRewardController);
        _setPOLParams(BASE_RATE, REWARD_RATE, MIN_BOOSTED_REWARD_RATE, BOOST_MULTIPLIER, REWARD_CONVEXITY);
    }
}
