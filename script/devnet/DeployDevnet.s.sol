// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { BaseDeployScript } from "script/base/BaseDeploy.s.sol";
import { RBAC } from "script/base/RBAC.sol";
import { Storage } from "script/base/Storage.sol";
import { AddressBook } from "script/base/AddressBook.sol";
import { ConfigPOL } from "script/pol/logic/ConfigPOL.sol";

import { BGT } from "src/pol/BGT.sol";
import { BGTDeployer } from "src/pol/BGTDeployer.sol";
import { POLDeployer } from "src/pol/POLDeployer.sol";
import { BGTFeeDeployer } from "src/pol/BGTFeeDeployer.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { BGTIncentiveDistributorDeployer } from "src/pol/BGTIncentiveDistributorDeployer.sol";
import { BGTIncentiveFeeDeployer } from "src/pol/BGTIncentiveFeeDeployer.sol";
import { WBERAStakerVault } from "src/pol/WBERAStakerVault.sol";
import { BGTIncentiveFeeCollector } from "src/pol/BGTIncentiveFeeCollector.sol";
import { DedicatedEmissionStreamManagerDeployer } from "src/pol/DedicatedEmissionStreamManagerDeployer.sol";
import { DedicatedEmissionStreamManager } from "src/pol/rewards/DedicatedEmissionStreamManager.sol";
import { RewardVaultHelperDeployer } from "src/pol/RewardVaultHelperDeployer.sol";
import { RewardVaultHelper } from "src/pol/rewards/RewardVaultHelper.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { WBERA } from "src/WBERA.sol";

import { HoneyDeployer } from "src/honey/HoneyDeployer.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HoneyFactoryReader } from "src/honey/HoneyFactoryReader.sol";

import { PeggedPriceOracle } from "src/extras/PeggedPriceOracle.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { PythPriceOracleDeployer } from "src/extras/PythPriceOracleDeployer.sol";
import { RootPriceOracle } from "src/extras/RootPriceOracle.sol";
import { RootPriceOracleDeployer } from "src/extras/RootPriceOracleDeployer.sol";

/// @notice Single-shot devnet deployment script.
/// @dev Deploys all system contracts, configures them, and transfers all ownership to `owner`.
/// Governance contracts (BerachainGovernance, TimeLock) are intentionally omitted.
///
/// Prerequisites:
///   - Broadcaster must have enough BERA to wrap 10 BERA → WBERA for the WBERAStakerVault initial deposit.
///   - WBERA (0x6969...) and BeaconDeposit (0x4242...) must be live at their genesis addresses.
///
/// Usage:
///   forge script script/devnet/DeployDevnet.s.sol \
///     --rpc-url $DEVNET_RPC \
///     --sig "run(address)" <OWNER_ADDRESS> \
///     --sender <DEPLOYER_ADDRESS> \
///     --broadcast
contract DeployDevnetScript is BaseDeployScript, RBAC, Storage, AddressBook, ConfigPOL {
    // ─── Genesis addresses ───

    /// @dev Wrapped BERA genesis address (same on all Berachain networks).
    address internal constant WBERA_ADDRESS = 0x6969696969696969696969696969696969696969;

    /// @dev BeaconDeposit genesis address.
    address internal constant BEACON_DEPOSIT_ADDRESS = 0x4242424242424242424242424242424242424242;

    // ─── Deployment constants ───

    /// @dev Payout amount for FeeCollector (WBERA per claim).
    uint256 internal constant PAYOUT_AMOUNT_FEE = 5000 ether;

    /// @dev Payout amount for BGTIncentiveFeeCollector (WBERA per claim).
    uint256 internal constant PAYOUT_AMOUNT_INCENTIVE = 50_000 ether;

    /// @dev Initial WBERA deposit to WBERAStakerVault to prevent inflation attacks.
    uint256 internal constant INITIAL_DEPOSIT_AMOUNT = 10 ether;

    /// @dev Block delay before a queued reward allocation becomes active in BeraChef.
    uint64 internal constant REWARD_ALLOCATION_BLOCK_DELAY = 8191;

    // BlockRewardController rates
    uint256 internal constant BASE_RATE = 0.5e18;
    uint256 internal constant REWARD_RATE = 3e18;
    uint256 internal constant MIN_BOOSTED_REWARD_RATE = 0;
    uint256 internal constant BOOST_MULTIPLIER = 3e18;
    uint256 internal constant REWARD_CONVEXITY = 1e18;

    /// @dev BGT incentive fee rate on RewardVaultFactory (10% in basis points).
    uint256 internal constant BGT_INCENTIVE_FEE_RATE = 1000; // 10% = 1000 bps

    // ─── Additional storage not in base Storage
    // ───────────────────────────────

    PeggedPriceOracle internal peggedPriceOracle;
    PythPriceOracle internal pythPriceOracle;
    RootPriceOracle internal rootPriceOracle;

    // ─── Entry point ───

    /// @notice Deploy all system contracts and transfer ownership to `owner`.
    /// @param owner The address that will own all deployed contracts. May equal msg.sender.
    function run(address owner) external broadcast {
        require(owner != address(0), "DeployDevnet: owner cannot be zero address");

        console2.log("\n========== DeployDevnet ==========");
        console2.log("Deployer (msg.sender):", msg.sender);
        console2.log("Owner (target):", owner);

        _validateCode("BeaconDeposit", BEACON_DEPOSIT_ADDRESS);
        _validateCode("WBERA", WBERA_ADDRESS);

        // ── Phase 1: BGT ──
        _deployBGT();

        // ── Phase 2: POL system ──
        _deployPOL();
        _deployBGTFees();
        _deployBGTIncentiveDistributor();
        _deployBGTIncentiveFees();
        _deployDedicatedEmissionStreamManager();
        _deployRewardVaultHelper();

        // ── Phase 3: Oracles ──
        _deployOracles();

        // ── Phase 4: Honey ──
        _deployHoney();

        // ── Phase 5: Configure setters ──
        _configure();

        // ── Phase 6: Transfer ownership to owner ──
        _transferAllOwnership(owner);

        console2.log("\n========== Deployment complete ==========");
        _logAddresses();
    }

    // ─── Phase 1: BGT ───

    function _deployBGT() internal {
        console2.log("\n--- [1/4] BGT ---");

        // msg.sender is the initial owner so it can call setMinter/setStaker/whitelistSender later.
        BGTDeployer bgtDeployer = new BGTDeployer(msg.sender, _salt(type(BGT).creationCode));
        bgt = bgtDeployer.bgt();
        _checkDeploymentAddress("BGT", address(bgt), _polAddresses.bgt);
    }

    // ─── Phase 2: POL system ───

    function _deployPOL() internal {
        console2.log("\n--- [2/4] PoL ---");

        // msg.sender passed as governance so it holds DEFAULT_ADMIN_ROLE for later setters.
        POLDeployer polDeployer = new POLDeployer(
            address(bgt),
            msg.sender,
            _saltsForProxy(type(BeraChef).creationCode),
            _saltsForProxy(type(BlockRewardController).creationCode),
            _saltsForProxy(type(Distributor).creationCode),
            _saltsForProxy(type(RewardVaultFactory).creationCode),
            _salt(type(RewardVault).creationCode)
        );

        beraChef = polDeployer.beraChef();
        _checkDeploymentAddress("BeraChef", address(beraChef), _polAddresses.beraChef);

        blockRewardController = polDeployer.blockRewardController();
        _checkDeploymentAddress(
            "BlockRewardController", address(blockRewardController), _polAddresses.blockRewardController
        );

        distributor = polDeployer.distributor();
        _checkDeploymentAddress("Distributor", address(distributor), _polAddresses.distributor);

        rewardVaultFactory = polDeployer.rewardVaultFactory();
        _checkDeploymentAddress("RewardVaultFactory", address(rewardVaultFactory), _polAddresses.rewardVaultFactory);

        // Grant operational roles to deployer.
        // VAULT_PAUSER_ROLE's admin is VAULT_MANAGER_ROLE, so we must hold VAULT_MANAGER_ROLE
        // to be able to transfer VAULT_PAUSER_ROLE in the ownership phase.
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        _grantRole(
            RBAC.RoleDescription({
                contractName: "RewardVaultFactory",
                contractAddr: address(rewardVaultFactory),
                name: "VAULT_MANAGER_ROLE",
                role: rewardVaultFactory.VAULT_MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "RewardVaultFactory",
                contractAddr: address(rewardVaultFactory),
                name: "VAULT_PAUSER_ROLE",
                role: rewardVaultFactory.VAULT_PAUSER_ROLE()
            }),
            deployer
        );
        // MANAGER_ROLE on Distributor (needed to transfer it in the ownership phase).
        _grantRole(
            RBAC.RoleDescription({
                contractName: "Distributor",
                contractAddr: address(distributor),
                name: "MANAGER_ROLE",
                role: distributor.MANAGER_ROLE()
            }),
            deployer
        );
    }

    function _deployBGTFees() internal {
        console2.log("\n--- [2/4] BGT fees ---");

        BGTFeeDeployer feeDeployer = new BGTFeeDeployer(
            address(bgt),
            msg.sender,
            WBERA_ADDRESS,
            _saltsForProxy(type(BGTStaker).creationCode),
            _saltsForProxy(type(FeeCollector).creationCode),
            PAYOUT_AMOUNT_FEE
        );

        bgtStaker = feeDeployer.bgtStaker();
        _checkDeploymentAddress("BGTStaker", address(bgtStaker), _polAddresses.bgtStaker);

        feeCollector = feeDeployer.feeCollector();
        _checkDeploymentAddress("FeeCollector", address(feeCollector), _polAddresses.feeCollector);

        // PAUSER_ROLE's admin is MANAGER_ROLE on FeeCollector.
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        _grantRole(
            RBAC.RoleDescription({
                contractName: "FeeCollector",
                contractAddr: address(feeCollector),
                name: "MANAGER_ROLE",
                role: feeCollector.MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "FeeCollector",
                contractAddr: address(feeCollector),
                name: "PAUSER_ROLE",
                role: feeCollector.PAUSER_ROLE()
            }),
            deployer
        );
    }

    function _deployBGTIncentiveDistributor() internal {
        console2.log("\n--- [2/4] BGTIncentiveDistributor ---");

        BGTIncentiveDistributorDeployer bgtIncDistDeployer = new BGTIncentiveDistributorDeployer(
            msg.sender, _saltsForProxy(type(BGTIncentiveDistributor).creationCode)
        );

        bgtIncentiveDistributor = bgtIncDistDeployer.bgtIncentiveDistributor();
        _checkDeploymentAddress(
            "BGTIncentiveDistributor", address(bgtIncentiveDistributor), _polAddresses.bgtIncentiveDistributor
        );

        // PAUSER_ROLE's admin is MANAGER_ROLE on BGTIncentiveDistributor.
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        _grantRole(
            RBAC.RoleDescription({
                contractName: "BGTIncentiveDistributor",
                contractAddr: address(bgtIncentiveDistributor),
                name: "MANAGER_ROLE",
                role: bgtIncentiveDistributor.MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "BGTIncentiveDistributor",
                contractAddr: address(bgtIncentiveDistributor),
                name: "PAUSER_ROLE",
                role: bgtIncentiveDistributor.PAUSER_ROLE()
            }),
            deployer
        );
    }

    function _deployBGTIncentiveFees() internal {
        console2.log("\n--- [2/4] BGTIncentiveFees ---");

        // Wrap BERA → WBERA; the BGTIncentiveFeeDeployer will pull INITIAL_DEPOSIT_AMOUNT via transferFrom.
        WBERA(payable(WBERA_ADDRESS)).deposit{ value: INITIAL_DEPOSIT_AMOUNT }();

        bytes memory args = abi.encode(
            msg.sender, // governance (DEFAULT_ADMIN_ROLE on both vaults)
            msg.sender, // tokenProvider (will transferFrom this address)
            PAYOUT_AMOUNT_INCENTIVE,
            _saltsForProxy(type(WBERAStakerVault).creationCode),
            _saltsForProxy(type(BGTIncentiveFeeCollector).creationCode)
        );

        // Must approve before deploying because the constructor calls transferFrom(tokenProvider).
        address predictedDeployer = _predictAddressWithArgs(type(BGTIncentiveFeeDeployer).creationCode, args);
        IERC20(WBERA_ADDRESS).approve(predictedDeployer, INITIAL_DEPOSIT_AMOUNT);

        BGTIncentiveFeeDeployer bgtIncFeeDeployer = BGTIncentiveFeeDeployer(
            _deployWithArgs(
                "BGTIncentiveFeeDeployer", type(BGTIncentiveFeeDeployer).creationCode, args, predictedDeployer
            )
        );

        wberaStakerVault = bgtIncFeeDeployer.wberaStakerVault();
        _checkDeploymentAddress("WBERAStakerVault", address(wberaStakerVault), _polAddresses.wberaStakerVault);

        bgtIncentiveFeeCollector = bgtIncFeeDeployer.bgtIncentiveFeeCollector();
        _checkDeploymentAddress(
            "BGTIncentiveFeeCollector", address(bgtIncentiveFeeCollector), _polAddresses.bgtIncentiveFeeCollector
        );

        // PAUSER_ROLE's admin is MANAGER_ROLE on both contracts.
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        _grantRole(
            RBAC.RoleDescription({
                contractName: "WBERAStakerVault",
                contractAddr: address(wberaStakerVault),
                name: "MANAGER_ROLE",
                role: wberaStakerVault.MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "WBERAStakerVault",
                contractAddr: address(wberaStakerVault),
                name: "PAUSER_ROLE",
                role: wberaStakerVault.PAUSER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "BGTIncentiveFeeCollector",
                contractAddr: address(bgtIncentiveFeeCollector),
                name: "MANAGER_ROLE",
                role: bgtIncentiveFeeCollector.MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "BGTIncentiveFeeCollector",
                contractAddr: address(bgtIncentiveFeeCollector),
                name: "PAUSER_ROLE",
                role: bgtIncentiveFeeCollector.PAUSER_ROLE()
            }),
            deployer
        );
    }

    function _deployDedicatedEmissionStreamManager() internal {
        console2.log("\n--- [2/4] DedicatedEmissionStreamManager ---");

        DedicatedEmissionStreamManagerDeployer desDeployer = new DedicatedEmissionStreamManagerDeployer(
            msg.sender,
            address(distributor),
            address(beraChef),
            _saltsForProxy(type(DedicatedEmissionStreamManager).creationCode)
        );

        dedicatedEmissionStreamManager = desDeployer.dedicatedEmissionStreamManager();
        _checkDeploymentAddress(
            "DedicatedEmissionStreamManager",
            address(dedicatedEmissionStreamManager),
            _polAddresses.dedicatedEmissionStreamManager
        );
    }

    function _deployRewardVaultHelper() internal {
        console2.log("\n--- [2/4] RewardVaultHelper ---");

        RewardVaultHelperDeployer rvhDeployer =
            new RewardVaultHelperDeployer(msg.sender, _saltsForProxy(type(RewardVaultHelper).creationCode));

        rewardVaultHelper = rvhDeployer.rewardVaultHelper();
        _checkDeploymentAddress("RewardVaultHelper", address(rewardVaultHelper), _polAddresses.rewardVaultHelper);
    }

    // ─── Phase 3: Oracles ───

    function _deployOracles() internal {
        console2.log("\n--- [3/4] Oracles ---");

        // PeggedPriceOracle: stateless, no proxy, pure CREATE2.
        _predictAddress(type(PeggedPriceOracle).creationCode);
        peggedPriceOracle = PeggedPriceOracle(
            _deploy("PeggedPriceOracle", type(PeggedPriceOracle).creationCode, _oraclesAddresses.peggedPriceOracle)
        );

        // PythPriceOracle: proxied, msg.sender gets DEFAULT_ADMIN_ROLE.
        PythPriceOracleDeployer pythDeployer =
            new PythPriceOracleDeployer(msg.sender, _saltsForProxy(type(PythPriceOracle).creationCode));
        pythPriceOracle = pythDeployer.oracle();
        _checkDeploymentAddress("PythPriceOracle", address(pythPriceOracle), _oraclesAddresses.pythPriceOracle);

        // RootPriceOracle: no proxy, CREATE2, msg.sender gets DEFAULT_ADMIN_ROLE.
        RootPriceOracleDeployer rootDeployer =
            new RootPriceOracleDeployer(msg.sender, _salt(type(RootPriceOracle).creationCode));
        rootPriceOracle = rootDeployer.rootPriceOracle();
        _checkDeploymentAddress("RootPriceOracle", address(rootPriceOracle), _oraclesAddresses.rootPriceOracle);

        // Grant MANAGER_ROLE to msg.sender on both oracles so it can call their restricted setters in _configure().
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        _grantRole(
            RBAC.RoleDescription({
                contractName: "PythPriceOracle",
                contractAddr: address(pythPriceOracle),
                name: "MANAGER_ROLE",
                role: pythPriceOracle.MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "RootPriceOracle",
                contractAddr: address(rootPriceOracle),
                name: "MANAGER_ROLE",
                role: rootPriceOracle.MANAGER_ROLE()
            }),
            deployer
        );
    }

    // ─── Phase 4: Honey ───

    function _deployHoney() internal {
        console2.log("\n--- [4/6] Honey ---");

        HoneyDeployer honeyDeployer = new HoneyDeployer(
            msg.sender,
            address(feeCollector),
            address(feeCollector),
            _saltsForProxy(type(Honey).creationCode),
            _saltsForProxy(type(HoneyFactory).creationCode),
            _saltsForProxy(type(HoneyFactoryReader).creationCode),
            address(peggedPriceOracle)
        );

        honey = honeyDeployer.honey();
        _checkDeploymentAddress("Honey", address(honey), _honeyAddresses.honey);

        honeyFactory = honeyDeployer.honeyFactory();
        _checkDeploymentAddress("HoneyFactory", address(honeyFactory), _honeyAddresses.honeyFactory);

        honeyFactoryReader = honeyDeployer.honeyFactoryReader();
        _checkDeploymentAddress("HoneyFactoryReader", address(honeyFactoryReader), _honeyAddresses.honeyFactoryReader);

        require(honeyFactory.feeReceiver() == address(feeCollector), "DeployDevnet: fee receiver not set");
        require(honeyFactory.polFeeCollector() == address(feeCollector), "DeployDevnet: pol fee collector not set");

        // PAUSER_ROLE's admin is MANAGER_ROLE on HoneyFactory.
        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        _grantRole(
            RBAC.RoleDescription({
                contractName: "HoneyFactory",
                contractAddr: address(honeyFactory),
                name: "MANAGER_ROLE",
                role: honeyFactory.MANAGER_ROLE()
            }),
            deployer
        );
        _grantRole(
            RBAC.RoleDescription({
                contractName: "HoneyFactory",
                contractAddr: address(honeyFactory),
                name: "PAUSER_ROLE",
                role: honeyFactory.PAUSER_ROLE()
            }),
            deployer
        );
    }

    // ─── Phase 5: Configure setters ───

    function _configure() internal {
        console2.log("\n--- [5/6] Configure ---");

        // BGT: set staker, whitelist distributor as sender, set minter.
        _setBGTAddresses(address(bgtStaker), address(distributor), address(blockRewardController));

        // BlockRewardController: set all reward rate parameters.
        _setPOLParams(BASE_RATE, REWARD_RATE, MIN_BOOSTED_REWARD_RATE, BOOST_MULTIPLIER, REWARD_CONVEXITY);

        // BeraChef: set the block delay for reward allocation activation.
        _setRewardAllocationBlockDelay(REWARD_ALLOCATION_BLOCK_DELAY);

        // Distributor: link to DedicatedEmissionStreamManager.
        distributor.setDedicatedEmissionStreamManager(address(dedicatedEmissionStreamManager));
        require(
            address(distributor.dedicatedEmissionStreamManager()) == address(dedicatedEmissionStreamManager),
            "DeployDevnet: dedicatedEmissionStreamManager not set on Distributor"
        );
        console2.log("Set DedicatedEmissionStreamManager on Distributor");

        // RewardVaultFactory: link incentive distributor, fee collector, fee rate and helper.
        rewardVaultFactory.setBGTIncentiveDistributor(address(bgtIncentiveDistributor));
        rewardVaultFactory.setBGTIncentiveFeeCollector(address(bgtIncentiveFeeCollector));
        rewardVaultFactory.setBGTIncentiveFeeRate(BGT_INCENTIVE_FEE_RATE);
        rewardVaultFactory.setRewardVaultHelper(address(rewardVaultHelper));
        console2.log("Configured RewardVaultFactory incentive settings");

        require(
            rewardVaultFactory.rewardVaultHelper() == address(rewardVaultHelper),
            "DeployDevnet: rewardVaultHelper not wired on RewardVaultFactory"
        );
        console2.log("Wired RewardVaultHelper on RewardVaultFactory");

        // RootPriceOracle: use PeggedPriceOracle as spot oracle (all assets pegged 1:1 on devnet).
        rootPriceOracle.setSpotOracle(address(peggedPriceOracle));
        console2.log("Set PeggedPriceOracle as spot oracle on RootPriceOracle");
    }

    // ─── Phase 6: Transfer ownership ───

    function _transferAllOwnership(address owner) internal {
        console2.log("\n--- [6/6] Transfer ownership to:", owner, "---");

        RBAC.AccountDescription memory deployer = RBAC.AccountDescription({ name: "deployer", addr: msg.sender });
        RBAC.AccountDescription memory ownerDesc = RBAC.AccountDescription({ name: "owner", addr: owner });

        // ── BGT (Ownable) ───
        bgt.transferOwnership(owner);
        require(bgt.owner() == owner, "DeployDevnet: BGT ownership transfer failed");
        console2.log("BGT ownership transferred");

        // ── BeraChef (Ownable) ───
        beraChef.transferOwnership(owner);
        require(beraChef.owner() == owner, "DeployDevnet: BeraChef ownership transfer failed");
        console2.log("BeraChef ownership transferred");

        // ── BlockRewardController (Ownable) ───
        blockRewardController.transferOwnership(owner);
        require(
            blockRewardController.owner() == owner, "DeployDevnet: BlockRewardController ownership transfer failed"
        );
        console2.log("BlockRewardController ownership transferred");

        // ── BGTStaker (Ownable) ───
        bgtStaker.transferOwnership(owner);
        require(bgtStaker.owner() == owner, "DeployDevnet: BGTStaker ownership transfer failed");
        console2.log("BGTStaker ownership transferred");

        // ── RewardVaultFactory (AccessControl) ──
        {
            RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
                contractName: "RewardVaultFactory",
                contractAddr: address(rewardVaultFactory),
                name: "VAULT_PAUSER_ROLE",
                role: rewardVaultFactory.VAULT_PAUSER_ROLE()
            });
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "RewardVaultFactory",
                contractAddr: address(rewardVaultFactory),
                name: "VAULT_MANAGER_ROLE",
                role: rewardVaultFactory.VAULT_MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "RewardVaultFactory",
                contractAddr: address(rewardVaultFactory),
                name: "DEFAULT_ADMIN_ROLE",
                role: rewardVaultFactory.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(pauserRole, deployer, ownerDesc);
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);

            UpgradeableBeacon rewardVaultBeacon = UpgradeableBeacon(rewardVaultFactory.beacon());
            rewardVaultBeacon.transferOwnership(owner);
            console2.log("RewardVaultFactory roles + beacon transferred");
        }

        // ── Distributor (AccessControl) ──
        {
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "Distributor",
                contractAddr: address(distributor),
                name: "MANAGER_ROLE",
                role: distributor.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "Distributor",
                contractAddr: address(distributor),
                name: "DEFAULT_ADMIN_ROLE",
                role: distributor.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("Distributor roles transferred");
        }

        // ── FeeCollector (AccessControl) ──
        {
            RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
                contractName: "FeeCollector",
                contractAddr: address(feeCollector),
                name: "PAUSER_ROLE",
                role: feeCollector.PAUSER_ROLE()
            });
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "FeeCollector",
                contractAddr: address(feeCollector),
                name: "MANAGER_ROLE",
                role: feeCollector.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "FeeCollector",
                contractAddr: address(feeCollector),
                name: "DEFAULT_ADMIN_ROLE",
                role: feeCollector.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(pauserRole, deployer, ownerDesc);
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("FeeCollector roles transferred");
        }

        // ── BGTIncentiveDistributor (AccessControl) ──
        {
            RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
                contractName: "BGTIncentiveDistributor",
                contractAddr: address(bgtIncentiveDistributor),
                name: "PAUSER_ROLE",
                role: bgtIncentiveDistributor.PAUSER_ROLE()
            });
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "BGTIncentiveDistributor",
                contractAddr: address(bgtIncentiveDistributor),
                name: "MANAGER_ROLE",
                role: bgtIncentiveDistributor.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "BGTIncentiveDistributor",
                contractAddr: address(bgtIncentiveDistributor),
                name: "DEFAULT_ADMIN_ROLE",
                role: bgtIncentiveDistributor.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(pauserRole, deployer, ownerDesc);
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("BGTIncentiveDistributor roles transferred");
        }

        // ── WBERAStakerVault (AccessControl) ──
        {
            RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
                contractName: "WBERAStakerVault",
                contractAddr: address(wberaStakerVault),
                name: "PAUSER_ROLE",
                role: wberaStakerVault.PAUSER_ROLE()
            });
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "WBERAStakerVault",
                contractAddr: address(wberaStakerVault),
                name: "MANAGER_ROLE",
                role: wberaStakerVault.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "WBERAStakerVault",
                contractAddr: address(wberaStakerVault),
                name: "DEFAULT_ADMIN_ROLE",
                role: wberaStakerVault.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(pauserRole, deployer, ownerDesc);
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("WBERAStakerVault roles transferred");
        }

        // ── BGTIncentiveFeeCollector (AccessControl) ──
        {
            RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
                contractName: "BGTIncentiveFeeCollector",
                contractAddr: address(bgtIncentiveFeeCollector),
                name: "PAUSER_ROLE",
                role: bgtIncentiveFeeCollector.PAUSER_ROLE()
            });
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "BGTIncentiveFeeCollector",
                contractAddr: address(bgtIncentiveFeeCollector),
                name: "MANAGER_ROLE",
                role: bgtIncentiveFeeCollector.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "BGTIncentiveFeeCollector",
                contractAddr: address(bgtIncentiveFeeCollector),
                name: "DEFAULT_ADMIN_ROLE",
                role: bgtIncentiveFeeCollector.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(pauserRole, deployer, ownerDesc);
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("BGTIncentiveFeeCollector roles transferred");
        }

        // ── DedicatedEmissionStreamManager (AccessControl) ──
        {
            RBAC.RoleDescription memory allocationManagerRole = RBAC.RoleDescription({
                contractName: "DedicatedEmissionStreamManager",
                contractAddr: address(dedicatedEmissionStreamManager),
                name: "ALLOCATION_MANAGER_ROLE",
                role: dedicatedEmissionStreamManager.ALLOCATION_MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "DedicatedEmissionStreamManager",
                contractAddr: address(dedicatedEmissionStreamManager),
                name: "DEFAULT_ADMIN_ROLE",
                role: dedicatedEmissionStreamManager.DEFAULT_ADMIN_ROLE()
            });
            _grantRole(allocationManagerRole, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("DedicatedEmissionStreamManager roles transferred");
        }

        // ── RewardVaultHelper (AccessControl) ──
        {
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "RewardVaultHelper",
                contractAddr: address(rewardVaultHelper),
                name: "DEFAULT_ADMIN_ROLE",
                role: rewardVaultHelper.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("RewardVaultHelper roles transferred");
        }

        // ── Honey (AccessControl) ──
        {
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "Honey",
                contractAddr: address(honey),
                name: "DEFAULT_ADMIN_ROLE",
                role: honey.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("Honey roles transferred");
        }

        // ── HoneyFactory (AccessControl) ──
        {
            RBAC.RoleDescription memory pauserRole = RBAC.RoleDescription({
                contractName: "HoneyFactory",
                contractAddr: address(honeyFactory),
                name: "PAUSER_ROLE",
                role: honeyFactory.PAUSER_ROLE()
            });
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "HoneyFactory",
                contractAddr: address(honeyFactory),
                name: "MANAGER_ROLE",
                role: honeyFactory.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "HoneyFactory",
                contractAddr: address(honeyFactory),
                name: "DEFAULT_ADMIN_ROLE",
                role: honeyFactory.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(pauserRole, deployer, ownerDesc);
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);

            UpgradeableBeacon honeyFactoryBeacon = UpgradeableBeacon(honeyFactory.beacon());
            honeyFactoryBeacon.transferOwnership(owner);
            console2.log("HoneyFactory roles + beacon transferred");
        }

        // ── HoneyFactoryReader (AccessControl) ──
        {
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "HoneyFactoryReader",
                contractAddr: address(honeyFactoryReader),
                name: "DEFAULT_ADMIN_ROLE",
                role: honeyFactoryReader.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("HoneyFactoryReader roles transferred");
        }

        // ── PythPriceOracle (AccessControl) ──
        {
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "PythPriceOracle",
                contractAddr: address(pythPriceOracle),
                name: "MANAGER_ROLE",
                role: pythPriceOracle.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "PythPriceOracle",
                contractAddr: address(pythPriceOracle),
                name: "DEFAULT_ADMIN_ROLE",
                role: pythPriceOracle.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("PythPriceOracle roles transferred");
        }

        // ── RootPriceOracle (AccessControl) ──
        {
            RBAC.RoleDescription memory managerRole = RBAC.RoleDescription({
                contractName: "RootPriceOracle",
                contractAddr: address(rootPriceOracle),
                name: "MANAGER_ROLE",
                role: rootPriceOracle.MANAGER_ROLE()
            });
            RBAC.RoleDescription memory adminRole = RBAC.RoleDescription({
                contractName: "RootPriceOracle",
                contractAddr: address(rootPriceOracle),
                name: "DEFAULT_ADMIN_ROLE",
                role: rootPriceOracle.DEFAULT_ADMIN_ROLE()
            });
            _transferRole(managerRole, deployer, ownerDesc);
            _transferRole(adminRole, deployer, ownerDesc);
            console2.log("RootPriceOracle roles transferred");
        }

        console2.log("\nAll ownership transferred to:", owner);
    }

    // ─── Helpers ───

    function _logAddresses() internal view {
        console2.log("\n--- Deployed addresses ---");
        console2.log("BGT:                             ", address(bgt));
        console2.log("BeraChef:                        ", address(beraChef));
        console2.log("BlockRewardController:           ", address(blockRewardController));
        console2.log("Distributor:                     ", address(distributor));
        console2.log("RewardVaultFactory:              ", address(rewardVaultFactory));
        console2.log("BGTStaker:                       ", address(bgtStaker));
        console2.log("FeeCollector:                    ", address(feeCollector));
        console2.log("BGTIncentiveDistributor:         ", address(bgtIncentiveDistributor));
        console2.log("WBERAStakerVault:                ", address(wberaStakerVault));
        console2.log("BGTIncentiveFeeCollector:        ", address(bgtIncentiveFeeCollector));
        console2.log("DedicatedEmissionStreamManager:  ", address(dedicatedEmissionStreamManager));
        console2.log("RewardVaultHelper:               ", address(rewardVaultHelper));
        console2.log("PeggedPriceOracle:               ", address(peggedPriceOracle));
        console2.log("PythPriceOracle:                 ", address(pythPriceOracle));
        console2.log("RootPriceOracle:                 ", address(rootPriceOracle));
        console2.log("Honey:                           ", address(honey));
        console2.log("HoneyFactory:                    ", address(honeyFactory));
        console2.log("HoneyFactoryReader:              ", address(honeyFactoryReader));
    }
}
