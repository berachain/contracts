// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./MockERC20.sol";
import { IDistributor } from "src/pol/interfaces/IDistributor.sol";

/// @dev For test purposes this contract simulate a malicius ERC20
/// that try to reentrancy attack the distributor contract
contract ReentrantERC20 is MockERC20 {
    address internal distributor;
    bytes internal pubkey;
    bool internal makeExternalCall;

    function setDistributeData(address distributor_, bytes calldata pubkey_) external {
        distributor = distributor_;
        pubkey = pubkey_;
    }

    function setMakeExternalCall(bool flag) external {
        makeExternalCall = flag;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (makeExternalCall) {
            IDistributor(distributor).distributeFor(pubkey);
        }
        return super.transfer(recipient, amount);
    }
}
