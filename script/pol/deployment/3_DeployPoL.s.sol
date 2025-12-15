// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { RBAC } from "../../base/RBAC.sol";
import { AddressBook } from "../../base/AddressBook.sol";
import { ConfigPOL } from "../logic/ConfigPOL.sol";
import { BGT } from "src/pol/BGT.sol";
import { POLDeployer } from "src/pol/POLDeployer.sol";
import { BGTFeeDeployer } from "src/pol/BGTFeeDeployer.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";

contract DeployPoLScript is BaseScript, ConfigPOL, RBAC, AddressBook {
    // NOTE: By default all POL params are set to 0

    // FeeCollector params
    // The amount to be paid out to the fee collector in order to claim fees.
    uint256 internal constant PAYOUT_AMOUNT = 5000 ether; // WBERA

    // BeraChef params
    // The block delay for activate queued reward allocation.
    uint64 internal constant REWARD_ALLOCATION_BLOCK_DELAY = 8191;

    function run() public broadcast {
        console2.log("BeaconDeposit: ", _polAddresses.beaconDeposit);
        _validateCode("BeaconDeposit", _polAddresses.beaconDeposit);
        console2.log("WBERA: ", _polAddresses.wbera);
        _validateCode("WBERA", _polAddresses.wbera);
        console2.log("BGT: ", _polAddresses.bgt);
        _validateCode("BGT", _polAddresses.bgt);

        bgt = BGT(_polAddresses.bgt);

        // deployment
        _deployPoL();
        _deployBGTFees();

        // configuration
        _setBGTAddresses(_polAddresses.bgtStaker, _polAddresses.distributor, _polAddresses.blockRewardController);
        _setRewardAllocationBlockDelay(REWARD_ALLOCATION_BLOCK_DELAY);
    }

    /// @dev Deploy main POL contract and initialize them
    function _deployPoL() internal {
        console2.log("\n\nDeploying PoL contracts...");

        console2.log("POLDeployer init code size", type(POLDeployer).creationCode.length);
        polDeployer = new POLDeployer(
            _polAddresses.bgt,
            msg.sender,
            _saltsForProxy(type(BeraChef).creationCode),
            _saltsForProxy(type(BlockRewardController).creationCode),
            _saltsForProxy(type(Distributor).creationCode),
            _saltsForProxy(type(RewardVaultFactory).creationCode),
            _salt(type(RewardVault).creationCode)
        );
        console2.log("POLDeployer deployed at:", address(polDeployer));

        beraChef = polDeployer.beraChef();
        _checkDeploymentAddress("BeraChef", address(beraChef), _polAddresses.beraChef);

        blockRewardController = polDeployer.blockRewardController();
        _checkDeploymentAddress(
            "BlockRewardController", address(blockRewardController), _polAddresses.blockRewardController
        );

        distributor = polDeployer.distributor();
        _checkDeploymentAddress("Distributor", address(distributor), _polAddresses.distributor);

        // Give roles to the deployer
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        // NOTE: the manager role on the distributor is not assigned to anyone, hence there is no need to revoke it.
        RBAC.RoleDescription memory distributorManagerRole = RBAC.RoleDescription({
            contractName: "Distributor",
            contractAddr: _polAddresses.distributor,
            name: "MANAGER_ROLE",
            role: distributor.MANAGER_ROLE()
        });

        _grantRole(distributorManagerRole, deployer);

        rewardVaultFactory = polDeployer.rewardVaultFactory();
        _checkDeploymentAddress("RewardVaultFactory", address(rewardVaultFactory), _polAddresses.rewardVaultFactory);

        RBAC.RoleDescription memory rewardVaultFactoryManagerRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: _polAddresses.rewardVaultFactory,
            name: "VAULT_MANAGER_ROLE",
            role: rewardVaultFactory.VAULT_MANAGER_ROLE()
        });
        RBAC.RoleDescription memory rewardVaultFactoryPauserRole = RBAC.RoleDescription({
            contractName: "RewardVaultFactory",
            contractAddr: _polAddresses.rewardVaultFactory,
            name: "VAULT_PAUSER_ROLE",
            role: rewardVaultFactory.VAULT_PAUSER_ROLE()
        });

        _grantRole(rewardVaultFactoryManagerRole, deployer);
        _grantRole(rewardVaultFactoryPauserRole, deployer);
    }

    /// @dev Deploy BGTStaker and FeeCollector
    function _deployBGTFees() internal {
        console2.log("\n\nDeploying BGTFeeDeployer...");

        console2.log("BGTFeeDeployer init code size", type(BGTFeeDeployer).creationCode.length);
        feeDeployer = new BGTFeeDeployer(
            _polAddresses.bgt,
            msg.sender,
            _polAddresses.wbera,
            _saltsForProxy(type(BGTStaker).creationCode),
            _saltsForProxy(type(FeeCollector).creationCode),
            PAYOUT_AMOUNT
        );
        console2.log("BGTFeeDeployer deployed at:", address(feeDeployer));

        bgtStaker = feeDeployer.bgtStaker();
        _checkDeploymentAddress("BGTStaker", address(bgtStaker), _polAddresses.bgtStaker);

        feeCollector = feeDeployer.feeCollector();
        _checkDeploymentAddress("FeeCollector", address(feeCollector), _polAddresses.feeCollector);

        console2.log("Set the payout amount to %d", PAYOUT_AMOUNT);

        // Give roles to the deployer
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });

        RBAC.RoleDescription memory feeCollectorManagerRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: _polAddresses.feeCollector,
            name: "MANAGER_ROLE",
            role: feeCollector.MANAGER_ROLE()
        });
        RBAC.RoleDescription memory feeCollectorPauserRole = RBAC.RoleDescription({
            contractName: "FeeCollector",
            contractAddr: _polAddresses.feeCollector,
            name: "PAUSER_ROLE",
            role: feeCollector.PAUSER_ROLE()
        });

        _grantRole(feeCollectorManagerRole, deployer);
        _grantRole(feeCollectorPauserRole, deployer);
    }
}
