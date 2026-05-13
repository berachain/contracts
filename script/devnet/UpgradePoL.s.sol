// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { BaseDeployScript } from "../base/BaseDeploy.s.sol";
import { AddressBook } from "../base/AddressBook.sol";
import { PoLUpgrader } from "./PoLUpgrader.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";

contract UpgradePoLScript is BaseDeployScript, AddressBook {
    address blockRewardControllerImpl;
    address beraChefImpl;
    address distributorImpl;
    address rewardVaultImpl;
    address rewardVaultFactoryImpl;
    address rewardVaultHelperImpl;

    function run() public pure {
        console2.log("Please run specific function.");
    }

    /// @notice Deploys new implementations for all PoL contracts without upgrading the proxies.
    function deployNewImplementations() public broadcast {
        _deployNewImplementations();
    }

    /// @notice Deploys PoLUpgrader, transfers all authorities to it, executes the upgrade, and
    ///         verifies that all authorities have been returned to the broadcaster.
    /// @dev    The broadcaster must already hold upgrade authority for every proxy (owner for
    ///         BlockRewardController / BeraChef; DEFAULT_ADMIN_ROLE for Distributor,
    ///         RewardVaultFactory, and RewardVaultHelper) and must own the RewardVault beacon.
    /// @param _blockRewardController Proxy address of BlockRewardController.
    /// @param _beraChef              Proxy address of BeraChef.
    /// @param _distributor           Proxy address of Distributor.
    /// @param _rewardVaultFactory    Proxy address of RewardVaultFactory.
    /// @param _rewardVaultHelper     Proxy address of RewardVaultHelper.
    /// @param _swbera                sWBERA token address.
    function upgrade(
        address payable _blockRewardController,
        address _beraChef,
        address _distributor,
        address _rewardVaultFactory,
        address payable _rewardVaultHelper,
        address _swbera
    )
        public
        broadcast
    {
        // ── 0. Deploy new implementations
        (
            blockRewardControllerImpl,
            beraChefImpl,
            distributorImpl,
            rewardVaultImpl,
            rewardVaultFactoryImpl,
            rewardVaultHelperImpl
        ) = _deployNewImplementations();

        // ── 1. Deploy PoLUpgrader (deploys all new implementations in its constructor)
        PoLUpgrader upgrader = new PoLUpgrader();
        console2.log("PoLUpgrader: ", address(upgrader));

        // ── 2. Transfer all authorities to the upgrader

        // Ownable contracts
        BlockRewardController(_blockRewardController).transferOwnership(address(upgrader));
        BeraChef(_beraChef).transferOwnership(address(upgrader));

        // Beacon (read before any factory upgrade so the address is still accessible)
        address beacon = RewardVaultFactory(_rewardVaultFactory).beacon();
        UpgradeableBeacon(beacon).transferOwnership(address(upgrader));

        // AccessControl contracts: grant to upgrader (broadcaster retains its own role)
        Distributor(_distributor).grantRole(bytes32(0), address(upgrader));
        RewardVaultFactory(_rewardVaultFactory).grantRole(bytes32(0), address(upgrader));
        RewardVaultHelper(_rewardVaultHelper).grantRole(bytes32(0), address(upgrader));

        // ── 3. Execute upgrade (upgrader returns all authorities to msg.sender = broadcaster)
        upgrader.upgrade(
            PoLUpgrader.Proxies({
                blockRewardController: _blockRewardController,
                beraChef: _beraChef,
                distributor: _distributor,
                rewardVaultFactory: _rewardVaultFactory,
                rewardVaultHelper: _rewardVaultHelper
            }),
            PoLUpgrader.Impls({
                blockRewardController: blockRewardControllerImpl,
                beraChef: beraChefImpl,
                distributor: distributorImpl,
                rewardVaultFactory: rewardVaultFactoryImpl,
                rewardVault: rewardVaultImpl,
                rewardVaultHelper: rewardVaultHelperImpl
            }),
            _swbera
        );

        // ── 4. Verify all authorities have been returned to the broadcaster
        require(BlockRewardController(_blockRewardController).owner() == msg.sender, "BRC: ownership not returned");
        require(BeraChef(_beraChef).owner() == msg.sender, "BeraChef: ownership not returned");
        require(UpgradeableBeacon(beacon).owner() == msg.sender, "Beacon: ownership not returned");
        require(Distributor(_distributor).hasRole(bytes32(0), msg.sender), "Distributor: admin not returned");
        require(
            RewardVaultFactory(_rewardVaultFactory).hasRole(bytes32(0), msg.sender),
            "RewardVaultFactory: admin not returned"
        );
        require(
            RewardVaultHelper(_rewardVaultHelper).hasRole(bytes32(0), msg.sender),
            "RewardVaultHelper: admin not returned"
        );

        console2.log("All authorities returned to:", msg.sender);
    }

    function _deployNewImplementations() internal returns (address, address, address, address, address, address) {
        address _blockRewardControllerImpl = address(new BlockRewardController());
        address _beraChefImpl = address(new BeraChef());
        address _distributorImpl = address(new Distributor());
        address _rewardVaultImpl = address(new RewardVault());
        address _rewardVaultFactoryImpl = address(new RewardVaultFactory());
        address _rewardVaultHelperImpl = address(new RewardVaultHelper());

        console2.log("BlockRewardController impl:", _blockRewardControllerImpl);
        console2.log("BeraChef impl:", _beraChefImpl);
        console2.log("Distributor impl:", _distributorImpl);
        console2.log("RewardVault impl:", _rewardVaultImpl);
        console2.log("RewardVaultFactory impl:", _rewardVaultFactoryImpl);
        console2.log("RewardVaultHelper impl:", _rewardVaultHelperImpl);

        return (
            _blockRewardControllerImpl,
            _beraChefImpl,
            _distributorImpl,
            _rewardVaultImpl,
            _rewardVaultFactoryImpl,
            _rewardVaultHelperImpl
        );
    }
}
