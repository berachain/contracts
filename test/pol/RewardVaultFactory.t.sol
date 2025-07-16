// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { MockRewardVault } from "test/mock/pol/MockRewardVault.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { RewardVaultFactory, IRewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { IPOLErrors } from "src/pol/interfaces/IRewardVaultFactory.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";
import { POLTest } from "./POL.t.sol";

contract RewardVaultFactoryTest is POLTest {
    MockHoney internal honey;
    address internal vaultManager = makeAddr("vaultManager");
    bytes32 internal constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 internal constant VAULT_PAUSER_ROLE = keccak256("VAULT_PAUSER_ROLE");

    function setUp() public override {
        super.setUp();
        honey = new MockHoney();
        vm.prank(governance);
        factory.grantRole(VAULT_MANAGER_ROLE, vaultManager);
    }

    function test_InitialState() public view {
        assertEq(factory.bgt(), address(bgt));
        assertEq(factory.distributor(), address(distributor));
        assertEq(factory.getVault(address(honey)), address(0));
        assert(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance));
    }

    function test_CreateRewardVault_RevertsIfStakingTokenIsNotAContract() public {
        // should revert with an EOA as staking token
        address eoa = makeAddr("EOA");
        vm.expectRevert(IPOLErrors.NotAContract.selector);
        factory.createRewardVault(eoa);

        // should revert with a zero address as staking token
        vm.expectRevert(IPOLErrors.NotAContract.selector);
        factory.createRewardVault(address(0));
    }

    function testFuzz_CreateRewardVault(address deployer) public {
        vm.prank(deployer);
        address vault = factory.createRewardVault(address(honey));
        assertEq(factory.predictRewardVaultAddress(address(honey)), vault);
        assertEq(factory.getVault(address(honey)), vault);
    }

    function test_CreateRewardVault_ReturnCachedIfAlreadyCreated() public {
        address firstCreation = test_CreateRewardVault();
        address secondCreation = factory.createRewardVault(address(honey));
        assertEq(firstCreation, secondCreation);
    }

    function test_CreateRewardVault() public returns (address vault) {
        address predictedAddress = factory.predictRewardVaultAddress(address(honey));
        vm.expectEmit();
        emit IRewardVaultFactory.VaultCreated(address(honey), predictedAddress);
        vault = factory.createRewardVault(address(honey));
        assertEq(predictedAddress, vault);
        assertEq(factory.getVault(address(honey)), vault);
    }

    function test_GetVaultsLength() public {
        assertEq(factory.allVaultsLength(), 0);
        test_CreateRewardVault();
        // creates 1 vault
        assertEq(factory.allVaultsLength(), 1);
    }

    function test_TransferOwnershipOfBeaconFailsIfNotOwner() public {
        address newAddress = makeAddr("newAddress");
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.transferOwnership(newAddress);
    }

    function test_TransferOwnershipOfBeaconFailsIfZeroAddress() public {
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.expectRevert(UpgradeableBeacon.NewOwnerIsZeroAddress.selector);
        vm.prank(governance);
        beacon.transferOwnership(address(0));
    }

    function test_TransferOwnershipOfBeacon() public {
        address newAddress = makeAddr("newAddress");
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.prank(governance);
        beacon.transferOwnership(newAddress);
        assertEq(beacon.owner(), newAddress);
    }

    function test_UpgradeBeaconProxyImplFailsIfNotOwner() public {
        address newImplementation = address(new MockRewardVault());
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        // implementation update of the beacon fails as caller is not the owner.
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.upgradeTo(newImplementation);
    }

    function test_UpgradeBeaconProxy() public returns (address vault, address beacon) {
        // deploy a rewardVault beaconProxy with an old implementation
        vault = test_CreateRewardVault();
        address newImplementation = address(new MockRewardVault());
        // update the implementation of the beacon
        beacon = factory.beacon();
        vm.prank(governance);
        // update the implementation of the beacon
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        // check the new implementation of the beacon
        assertEq(MockRewardVault(vault).VERSION(), 2);
        assertEq(MockRewardVault(vault).isNewImplementation(), true);
    }

    function test_UpgradeAndDowngradeOfBeaconProxy() public {
        (address vault, address beacon) = test_UpgradeBeaconProxy();
        // downgrade the implementation of the beacon
        address oldImplementation = address(new RewardVault());
        vm.prank(governance);
        UpgradeableBeacon(beacon).upgradeTo(oldImplementation);
        // Call will revert as old implementation does not have isNewImplementation function.
        vm.expectRevert();
        MockRewardVault(vault).isNewImplementation();
    }

    function test_UpgradeToFailsIfNotOwner() public {
        testFuzz_UpgradeToFailsIfNotOwner(address(this));
    }

    function testFuzz_UpgradeToFailsIfNotOwner(address caller) public {
        vm.assume(caller != governance);
        address newImplementation = address(new RewardVaultFactory());
        bytes32 role = factory.DEFAULT_ADMIN_ROLE();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, role));
        factory.upgradeToAndCall(newImplementation, bytes(""));
    }

    function test_UpgradeToFailsIfImplIsNotUUPS() public {
        vm.prank(governance);
        // call will revert as new implementation is not UUPS.
        vm.expectRevert();
        factory.upgradeToAndCall(address(this), bytes(""));
    }

    function test_UpgradeToAndCall() public {
        address newImplementation = address(new RewardVaultFactory());
        vm.prank(governance);
        vm.expectEmit();
        emit IERC1967.Upgraded(newImplementation);
        factory.upgradeToAndCall(newImplementation, bytes(""));
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address _implementation = address(uint160(uint256(vm.load(address(factory), slot))));
        assertEq(_implementation, newImplementation);
    }

    function test_GrantVaultPauserRoleFailWithGovernance() public {
        address newVaultPauser = makeAddr("newVaultPauser");
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, governance, VAULT_MANAGER_ROLE
            )
        );
        factory.grantRole(VAULT_PAUSER_ROLE, newVaultPauser);
    }

    function test_GrantVaultPauserRole() public {
        address newVaultPauser = makeAddr("newVaultPauser");
        vm.prank(vaultManager);
        factory.grantRole(VAULT_PAUSER_ROLE, newVaultPauser);
        assert(factory.hasRole(VAULT_PAUSER_ROLE, newVaultPauser));
    }

    function test_SetBGTIncentiveFeeRate_FailIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.setBGTIncentiveFeeRate(1000);
    }

    function test_SetBGTIncentiveFeeRate_FailInvalidRate() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.InvalidIncentiveFeeRate.selector));
        factory.setBGTIncentiveFeeRate(10_001);
    }

    function testFuzz_SetBGTIncentiveFeeRate(uint256 rate) public {
        rate = bound(rate, 0, 7000);
        assertEq(0, factory.bgtIncentiveFeeRate());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IRewardVaultFactory.IncentiveFeeRateUpdated(rate, 0);
        factory.setBGTIncentiveFeeRate(rate);
        assertEq(rate, factory.bgtIncentiveFeeRate());
    }

    function test_SetBGTIncentiveFeeCollector_FailIfNotAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), factory.DEFAULT_ADMIN_ROLE()
            )
        );
        factory.setBGTIncentiveFeeCollector(address(this));
    }

    function test_SetBGTIncentiveFeeCollector_FailIfZero() public {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IPOLErrors.ZeroAddress.selector));
        factory.setBGTIncentiveFeeCollector(address(0));
    }

    function testFuzz_SetBGTIncentiveFeeCollector(uint256 collectorInt) public {
        collectorInt = bound(collectorInt, 1, type(uint160).max);
        address collector = address(uint160(collectorInt));
        assertEq(address(0), factory.bgtIncentiveFeeCollector());
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IRewardVaultFactory.IncentiveFeeCollectorUpdated(collector, address(0));
        factory.setBGTIncentiveFeeCollector(collector);
        assertEq(collector, factory.bgtIncentiveFeeCollector());
    }

    function testFuzz_GetIncentiveFeeAmount(uint256 rate, uint256 incentiveAmount) public {
        incentiveAmount = bound(incentiveAmount, 1, type(uint256).max / 10_000);
        testFuzz_SetBGTIncentiveFeeRate(rate);
        rate = factory.bgtIncentiveFeeRate();

        uint256 feeAmount = factory.getIncentiveFeeAmount(incentiveAmount);
        assertEq(rate * incentiveAmount / 10_000, feeAmount);
    }
}
