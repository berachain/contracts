// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { LSTStakerVault } from "src/pol/lst/LSTStakerVault.sol";
import { LSTStakerVaultFactory } from "src/pol/lst/LSTStakerVaultFactory.sol";
import { LSTStakerVaultFactoryDeployer } from "src/pol/lst/LSTStakerVaultFactoryDeployer.sol";
import { LSTStakerVaultWithdrawalRequest } from "src/pol/lst/LSTStakerVaultWithdrawalRequest.sol";
import { MockLST } from "../mock/pol/lst/MockLST.sol";
import { Salt } from "src/base/Salt.sol";

import { MockTestnetLSTDeployer, MockTestnetLST } from "test/mock/pol/lst/MockTestnetLST.sol";

contract LSTStakerVaultFactoryTest is Test, Create2Deployer {
    LSTStakerVaultFactory factory;
    LSTStakerVault vault;
    LSTStakerVaultWithdrawalRequest withdrawal721;
    MockLST mockLst;

    address governance = makeAddr("governance");
    address public manager = makeAddr("manager");
    address public pauser = makeAddr("pauser");

    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");
    bytes32 public constant VAULT_PAUSER_ROLE = keccak256("VAULT_PAUSER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        _deployFactory();
    }

    function test_initialization() public view {
        assertTrue(factory.hasRole(DEFAULT_ADMIN_ROLE, governance));
        assertEq(DEFAULT_ADMIN_ROLE, factory.getRoleAdmin(VAULT_MANAGER_ROLE));
        assertEq(VAULT_MANAGER_ROLE, factory.getRoleAdmin(VAULT_PAUSER_ROLE));
    }

    function test_UpgradeTo_FailsIfNotAdmin() public {
        address newImplementation = address(new LSTStakerVaultFactory());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.upgradeToAndCall(newImplementation, bytes(""));
    }

    function test_UpgradeToAndCall() public {
        address newImplementation = address(new LSTStakerVaultFactory());
        vm.prank(governance);
        vm.expectEmit();
        emit IERC1967.Upgraded(newImplementation);
        factory.upgradeToAndCall(newImplementation, bytes(""));
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address _implementation = address(uint160(uint256(vm.load(address(factory), slot))));
        assertEq(_implementation, newImplementation);
    }

    function test_GrantManager_FailIfNotAdmin() public {
        address newVaultManager = makeAddr("newVaultManager");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.grantRole(VAULT_MANAGER_ROLE, newVaultManager);
    }

    function testFuzz_GrantManager(address newVaultManager) public {
        vm.assume(newVaultManager != address(0));
        vm.prank(governance);
        factory.grantRole(VAULT_MANAGER_ROLE, newVaultManager);
        assert(factory.hasRole(VAULT_MANAGER_ROLE, newVaultManager));
    }

    function test_GrantPauser_FailIfNotManager() public {
        address newVaultPauser = makeAddr("newVaultPauser");
        vm.prank(governance);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, governance, VAULT_MANAGER_ROLE
            )
        );
        factory.grantRole(VAULT_PAUSER_ROLE, newVaultPauser);
    }

    function test_GrantPauser() public {
        address newVaultManager = makeAddr("newVaultManager");
        testFuzz_GrantManager(newVaultManager);

        address newVaultPauser = makeAddr("newVaultPauser");
        vm.prank(newVaultManager);
        factory.grantRole(VAULT_PAUSER_ROLE, newVaultPauser);
        assert(factory.hasRole(VAULT_PAUSER_ROLE, newVaultPauser));
    }

    function test_CreateLSTStakerVaultSystem_FailsIfNotAdmin() public {
        mockLst = new MockLST();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.createLSTStakerVaultSystem(address(mockLst));
    }

    function test_CreateLSTStakerVaultSystem_FailsIfStakingTokenNotAContract() public {
        // should revert with an EOA as staking token
        address eoa = makeAddr("EOA");
        vm.expectRevert(IPOLErrors.NotAContract.selector);
        vm.prank(governance);
        factory.createLSTStakerVaultSystem(eoa);

        // should revert with a zero address as staking token
        vm.expectRevert(IPOLErrors.NotAContract.selector);
        vm.prank(governance);
        factory.createLSTStakerVaultSystem(address(0));
    }

    function test_CreateLSTStakerVaultSystem_ReturnCachedIfAlreadyCreated() public {
        test_CreateLSTStakerVaultSystem();
        address lst = vault.asset();
        LSTStakerVaultFactory.LSTAddresses memory secondCreation = _deployVault(lst);

        assertEq(address(vault), secondCreation.vault);
        assertEq(address(withdrawal721), secondCreation.withdrawal721);
    }

    function test_CreateLSTStakerVaultSystem() public {
        mockLst = new MockLST();
        _deployVault(address(mockLst));

        assertEq(factory.allLSTStakerContractsLength(), 1);

        (address vaultAddr, address withdrawal721Addr) = factory.allLSTStakerContracts(0);
        LSTStakerVaultFactory.LSTAddresses memory addrs = factory.getLSTStakerContracts(address(mockLst));

        assertEq(vaultAddr, addrs.vault);
        assertEq(withdrawal721Addr, addrs.withdrawal721);

        assertEq(address(vault), vaultAddr);
        assertEq(address(withdrawal721), withdrawal721Addr);

        // Check vault and withdrawal contract initialization
        assertEq("POL Staked mLST", vault.name());
        assertEq("smLST", vault.symbol());
        assertEq(18, vault.decimals());
        assertEq(address(mockLst), IERC4626(vault).asset());
        assertEq(7 days, vault.WITHDRAWAL_COOLDOWN());
        assertEq(address(withdrawal721), address(vault.withdrawalRequests721()));

        assertEq("POL Staked mLST Withdrawal Request", withdrawal721.name());
        assertEq("smLSTwr", withdrawal721.symbol());
        assertEq(address(vault), address(withdrawal721.stakerVault()));
        assertEq(7 days, withdrawal721.WITHDRAWAL_COOLDOWN());

        assertTrue(vault.isFactoryOwner(governance));
        assertTrue(withdrawal721.isFactoryOwner(governance));
    }

    function test_PredictStakerVaultAddress() public {
        mockLst = new MockLST();
        address predictedAddress = factory.predictStakerVaultAddress(address(mockLst));

        _deployVault(address(mockLst));
        assertEq(predictedAddress, address(vault));
    }

    function test_PredictWithdrawalRequestAddress() public {
        mockLst = new MockLST();
        address predictedAddress = factory.predictWithdrawalRequestAddress(address(mockLst));

        _deployVault(address(mockLst));
        assertEq(predictedAddress, address(withdrawal721));
    }

    function _deployFactory() internal {
        // Deploy factory
        Salt memory salt = Salt({ implementation: 0, proxy: 0 });
        LSTStakerVaultFactoryDeployer deployer = new LSTStakerVaultFactoryDeployer(governance, salt, 0, 0);
        factory = deployer.lstVaultFactory();
    }

    function _deployVault(address lst) internal returns (LSTStakerVaultFactory.LSTAddresses memory) {
        MockLST(lst).mint(governance, 10 ether);

        // Deploy vault and withdrawal contract
        vm.startPrank(governance);
        MockLST(lst).approve(address(factory), 10 ether);
        LSTStakerVaultFactory.LSTAddresses memory lstAddresses = factory.createLSTStakerVaultSystem(address(lst));
        vm.stopPrank();

        vault = LSTStakerVault(lstAddresses.vault);
        withdrawal721 = LSTStakerVaultWithdrawalRequest(lstAddresses.withdrawal721);
        return lstAddresses;
    }

    function test_MockTestnetLST() public {
        MockTestnetLSTDeployer deployer = new MockTestnetLSTDeployer(address(this));
        MockTestnetLST lst = MockTestnetLST(payable(deployer.lst()));

        address receiver = makeAddr("receiver");
        vm.deal(receiver, 1 ether);
        vm.prank(receiver);
        uint256 shares = lst.mint{ value: 1 ether }(receiver);

        assertEq(shares, lst.previewDeposit(1 ether));
        assertEq(lst.balanceOf(receiver), shares);
        assertEq(1 ether, lst.totalAssets());

        vm.warp(block.timestamp + 365 days);

        assertEq(1.05 ether, lst.totalAssets());
        assertApproxEqAbs(1.05 ether, lst.previewRedeem(lst.balanceOf(receiver)), 1);
    }
}
