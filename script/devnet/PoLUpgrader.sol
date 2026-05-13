// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { Ownable } from "solady/src/auth/Ownable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title PoLUpgrader
/// @notice Deploys new PoL implementations on construction, then upgrades all proxies and returns
///         all authorities to the caller in a single `upgrade()` transaction.
/// @dev Usage:
///      1. Deploy this contract — new implementations are deployed in the constructor.
///      2. Transfer upgrade authority for every proxy to this contract:
///         - `transferOwnership(address(this))` for BlockRewardController, BeraChef, and the RewardVault beacon.
///         - `grantRole(DEFAULT_ADMIN_ROLE, address(this))` for Distributor, RewardVaultFactory, RewardVaultHelper.
///      3. Call `upgrade(...)` — upgrades all proxies and returns all authorities to `msg.sender`.
contract PoLUpgrader {
    struct Proxies {
        address payable blockRewardController;
        address beraChef;
        address distributor;
        address rewardVaultFactory;
        address payable rewardVaultHelper;
    }

    struct Impls {
        address blockRewardController;
        address beraChef;
        address distributor;
        address rewardVaultFactory;
        address rewardVault;
        address rewardVaultHelper;
    }

    /// @dev Only the deployer may call `upgrade()`.
    // solhint-disable-next-line immutable-vars-naming
    address private immutable _deployer;

    constructor() {
        _deployer = msg.sender;
    }

    /// @notice Upgrades all PoL proxies and returns all authorities to `msg.sender`.
    /// @dev Must be called by the deployer. Caller must have transferred all upgrade authorities
    ///      to this contract before calling (see contract-level NatSpec).
    function upgrade(Proxies calldata proxies, Impls calldata impls, address _swbera) external {
        require(msg.sender == _deployer, "PoLUpgrader: not deployer");

        // ── Upgrade all proxies
        // ──────────────────────────────────────────────────

        // BlockRewardController: upgrade with V2 reinitializer that wires WBERA and clears deprecated state.
        // Use encodeWithSignature to disambiguate from the V1 initializer overload.
        UUPSUpgradeable(proxies.blockRewardController)
            .upgradeToAndCall(impls.blockRewardController, abi.encodeWithSignature("initialize()"));

        // Distributor: upgrade then update emission token to WBERA.
        UUPSUpgradeable(proxies.distributor)
            .upgradeToAndCall(impls.distributor, abi.encodeWithSignature("setEmissionToken()"));

        // BeraChef: plain upgrade, no reinitializer needed.
        UUPSUpgradeable(proxies.beraChef).upgradeToAndCall(impls.beraChef, "");

        // RewardVault: beacon upgrade — all vault proxies automatically use the new implementation.
        // Beacon address is read before upgrading the factory proxy.
        address beacon = RewardVaultFactory(proxies.rewardVaultFactory).beacon();
        UpgradeableBeacon(beacon).upgradeTo(impls.rewardVault);

        // RewardVaultFactory: plain upgrade.
        UUPSUpgradeable(proxies.rewardVaultFactory).upgradeToAndCall(impls.rewardVaultFactory, "");

        // RewardVaultHelper: upgrade then set sWBERA.
        UUPSUpgradeable(proxies.rewardVaultHelper)
            .upgradeToAndCall(impls.rewardVaultHelper, abi.encodeWithSignature("setSWBERA(address)", _swbera));

        // ── Return all authorities to msg.sender
        // ──────────────────────────────────────────────────

        // Ownable contracts
        Ownable(proxies.blockRewardController).transferOwnership(msg.sender);
        Ownable(proxies.beraChef).transferOwnership(msg.sender);
        UpgradeableBeacon(beacon).transferOwnership(msg.sender);

        // AccessControl contracts: grant first, then revoke to avoid losing admin role
        bytes32 adminRole = 0x00;
        IAccessControl(proxies.distributor).grantRole(adminRole, msg.sender);
        IAccessControl(proxies.distributor).revokeRole(adminRole, address(this));
        IAccessControl(proxies.rewardVaultFactory).grantRole(adminRole, msg.sender);
        IAccessControl(proxies.rewardVaultFactory).revokeRole(adminRole, address(this));
        IAccessControl(proxies.rewardVaultHelper).grantRole(adminRole, msg.sender);
        IAccessControl(proxies.rewardVaultHelper).revokeRole(adminRole, address(this));
    }
}
