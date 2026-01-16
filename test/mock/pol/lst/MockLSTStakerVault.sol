// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IStakerVault } from "src/pol/interfaces/lst/IStakerVault.sol";
import { IStakerVaultWithdrawalRequest } from "src/pol/interfaces/lst/IStakerVaultWithdrawalRequest.sol";

contract MockLSTStakerVault is IStakerVault, ERC4626 {
    constructor(address asset_) ERC4626(IERC20(asset_)) ERC20("Mock LST Staker Vault", "smLST") { }

    function recoverERC20(
        address,
        /* tokenAddress */
        uint256 /* tokenAmount */
    )
        external
        pure { }
    function setWithdrawalRequests721(
        address /* withdrawalRequests_ */
    )
        external
        pure { }
    function pause() external pure { }
    function unpause() external pure { }

    function receiveRewards(uint256 amount) external {
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
    }

    function queueRedeem(
        uint256, /* shares */
        address, /* receiver */
        address /* owner */
    )
        external
        pure
        returns (uint256 assets, uint256 withdrawalId)
    {
        return (0, 0);
    }

    function queueWithdraw(
        uint256, /* assets */
        address, /* receiver */
        address /* owner */
    )
        external
        pure
        returns (uint256 shares, uint256 withdrawalId)
    {
        return (0, 0);
    }

    function cancelQueuedWithdrawal(uint256 requestId) external { }
    function completeWithdrawal(uint256 requestId) external { }

    function WITHDRAWAL_COOLDOWN() external pure returns (uint256) {
        return 0;
    }

    function reservedAssets() external pure returns (uint256) {
        return 0;
    }

    function getERC721WithdrawalRequest(
        uint256 /* requestId */
    )
        external
        pure
        returns (IStakerVaultWithdrawalRequest.WithdrawalRequest memory)
    {
        return IStakerVaultWithdrawalRequest.WithdrawalRequest(0, 0, 0, address(0), address(0));
    }

    function getUserERC721WithdrawalRequestCount(
        address /* user */
    )
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function getERC721WithdrawalRequestIds(
        address /* user */
    )
        external
        pure
        returns (uint256[] memory)
    {
        return new uint256[](0);
    }

    function getERC721WithdrawalRequestIds(
        address, /* user */
        uint256, /* offset */
        uint256 /* limit */
    )
        external
        pure
        returns (uint256[] memory)
    {
        return new uint256[](0);
    }
}
