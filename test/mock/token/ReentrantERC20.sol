// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./MockERC20.sol";
import { IDistributor } from "src/pol/interfaces/IDistributor.sol";

/// @dev For test purposes this contract simulate a malicious ERC20
/// that try to reentrancy attack the distributor contract
contract ReentrantERC20 is MockERC20 {
    address internal distributor;
    uint64 internal timestamp;
    uint64 internal proposerIndex;
    bytes internal pubkey;
    bytes32[] internal proposerIndexProof;
    bytes32[] internal pubkeyProof;
    bool internal makeExternalCall;

    function setDistributeData(
        address distributor_,
        uint64 timestamp_,
        uint64 proposerIndex_,
        bytes calldata pubkey_,
        bytes32[] calldata proposerIndexProof_,
        bytes32[] calldata pubkeyProof_
    )
        external
    {
        distributor = distributor_;
        timestamp = timestamp_;
        proposerIndex = proposerIndex_;
        pubkey = pubkey_;
        proposerIndexProof = proposerIndexProof_;
        pubkeyProof = pubkeyProof_;
    }

    function setMakeExternalCall(bool flag) external {
        makeExternalCall = flag;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (makeExternalCall) {
            IDistributor(distributor).distributeFor(timestamp, proposerIndex, pubkey, proposerIndexProof, pubkeyProof);
        }
        return super.transfer(recipient, amount);
    }
}
