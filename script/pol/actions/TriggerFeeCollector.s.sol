// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Storage } from "../../base/Storage.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { AddressBook } from "../../base/AddressBook.sol";

/// @notice Claim fees and donate from/to FeeCollector
contract TriggerFeeCollector is BaseScript, Storage, AddressBook {
    // Placeholder. Change before running the script.
    bool internal constant DONATE_TO_FEE_COLLECTOR = true;
    uint256 internal constant DONATE_AMOUNT = 69_420 ether;

    mapping(address => uint256) public feeCollectorBalances;
    mapping(address => uint256) public userBalancesBeforeClaim;

    address[] internal _feeTokens = [address(0)];

    constructor() AddressBook(_chainType) { }

    function run() public broadcast {
        _validateCode("FeeCollector", _polAddresses.feeCollector);
        feeCollector = FeeCollector(_polAddresses.feeCollector);

        claimFees(_feeTokens);

        if (DONATE_TO_FEE_COLLECTOR) {
            donate(DONATE_AMOUNT);
        }
    }

    function claimFees(address[] memory feeTokens) internal {
        address payoutToken = feeCollector.payoutToken();
        uint256 payoutAmount = feeCollector.payoutAmount();

        approveToFeeCollector(payoutToken, payoutAmount);

        for (uint256 i; i < feeTokens.length; ++i) {
            feeCollectorBalances[feeTokens[i]] = IERC20(feeTokens[i]).balanceOf(_polAddresses.feeCollector);
            userBalancesBeforeClaim[feeTokens[i]] = IERC20(feeTokens[i]).balanceOf(msg.sender);
        }

        feeCollector.claimFees(msg.sender, feeTokens);
        console2.log("Claimed fees");

        for (uint256 i; i < feeTokens.length; ++i) {
            uint256 expectedUserBalanceAfterClaim =
                userBalancesBeforeClaim[feeTokens[i]] + feeCollectorBalances[feeTokens[i]];
            uint256 userBalanceAfterClaim = IERC20(feeTokens[i]).balanceOf(msg.sender);
            require(
                userBalanceAfterClaim == expectedUserBalanceAfterClaim, "TriggerFeeCollector: user balance mismatch"
            );
        }
    }

    function donate(uint256 amount) internal {
        address payoutToken = feeCollector.payoutToken();
        approveToFeeCollector(payoutToken, amount);
        feeCollector.donate(amount);
        console2.log("Donated %d", amount);
    }

    function approveToFeeCollector(address token, uint256 amount) internal {
        require(IERC20(token).balanceOf(msg.sender) >= amount, "Insufficient balance");
        IERC20(token).approve(_polAddresses.feeCollector, amount);
        console2.log("Approved %d of %s to FeeCollector", amount, token);
    }
}
