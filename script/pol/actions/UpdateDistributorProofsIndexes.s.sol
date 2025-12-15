// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { Storage } from "../../base/Storage.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { AddressBook } from "../../base/AddressBook.sol";

contract UpdateDistributorProofsIndexes is BaseScript, Storage, AddressBook {
    uint64 internal constant ZERO_VALIDATOR_PUBKEY_G_INDEX = 6_350_779_162_034_176;
    uint64 internal constant PROPOSER_INDEX_G_INDEX = 9;

    function run() public virtual broadcast {
        console2.log("Run specific script to update distributor proofs indexes:");
        console2.log("- setZeroValidatorPubkeyGIndex()");
        console2.log("- setProposerIndexGIndex()");
    }

    function setZeroValidatorPubkeyGIndex() public broadcast {
        Distributor distributor = Distributor(_polAddresses.distributor);
        console2.log("Distributor address: ", address(distributor));
        distributor.setZeroValidatorPubkeyGIndex(ZERO_VALIDATOR_PUBKEY_G_INDEX);
        console2.log("Zero validator pubkey gindex set to: ", ZERO_VALIDATOR_PUBKEY_G_INDEX);
    }

    function setProposerIndexGIndex() public broadcast {
        Distributor distributor = Distributor(_polAddresses.distributor);
        console2.log("Distributor address: ", address(distributor));
        distributor.setProposerIndexGIndex(PROPOSER_INDEX_G_INDEX);
        console2.log("Proposer index gindex set to: ", PROPOSER_INDEX_G_INDEX);
    }
}
