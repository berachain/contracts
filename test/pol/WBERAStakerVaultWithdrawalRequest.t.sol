// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IERC721Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { MockERC20 } from "../mock/token/MockERC20.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { WBERAStakerVaultWithdrawalRequest } from "src/pol/WBERAStakerVaultWithdrawalRequest.sol";
import { IWBERAStakerVaultWithdrawalRequest } from "src/pol/interfaces/IWBERAStakerVaultWithdrawalRequest.sol";

contract WBERAStakerVaultWithdrawalRequestTest is Test, Create2Deployer {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONTRACTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    WBERAStakerVaultWithdrawalRequest public withdrawals721;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       TEST ACCOUNTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address public owner = makeAddr("owner");
    address public caller = makeAddr("caller");
    address public receiver = makeAddr("receiver");
    address public governance = makeAddr("governance");
    address public stakerVault = makeAddr("stakerVault");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 public constant WITHDRAWAL_COOLDOWN = 7 days;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           SETUP                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setUp() public {
        _deployContracts();
    }

    function _deployContracts() internal {
        // WBERAStakerVaultWithdrawalRequest
        WBERAStakerVaultWithdrawalRequest withdrawals721Impl = new WBERAStakerVaultWithdrawalRequest();
        withdrawals721 = WBERAStakerVaultWithdrawalRequest(deployProxyWithCreate2(address(withdrawals721Impl), 0));

        // Initialize
        withdrawals721.initialize(governance, stakerVault);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _assertWithdrawalRequest(
        uint256 withdrawalId,
        uint256 expectedAssets,
        uint256 expectedShares,
        uint256 expectedTime,
        address expectedOwner,
        address expectedReceiver
    )
        internal
        view
    {
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawals721.getRequest(withdrawalId);

        assertEq(request.assets, expectedAssets);
        assertEq(request.shares, expectedShares);
        assertEq(request.requestTime, expectedTime);
        assertEq(request.owner, expectedOwner);
        assertEq(request.receiver, expectedReceiver);
    }

    function _assertWithdrawalRequestCleared(uint256 withdrawalId) internal view {
        IWBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawals721.getRequest(withdrawalId);
        assertEq(request.assets, 0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INITIALIZATION TESTS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_initialization() public view {
        assertEq(withdrawals721.name(), "POL Staked WBERA Withdrawal Request");
        assertEq(withdrawals721.symbol(), "sWBERAwr");
        assertEq(withdrawals721.WITHDRAWAL_COOLDOWN(), WITHDRAWAL_COOLDOWN);
        assertTrue(withdrawals721.owner() == governance);
    }

    function test_initializationWithZeroAddress() public {
        WBERAStakerVaultWithdrawalRequest impl = new WBERAStakerVaultWithdrawalRequest();
        WBERAStakerVaultWithdrawalRequest prox =
            WBERAStakerVaultWithdrawalRequest(deployProxyWithCreate2(address(impl), 0));

        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        prox.initialize(address(0), stakerVault);

        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        prox.initialize(governance, address(0));
    }

    function test_cannotInitializeTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        withdrawals721.initialize(governance, stakerVault);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    ADMIN FUNCTIONS TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_upgrade_FailsIfNotOwner() public {
        address newImpl = address(new WBERAStakerVaultWithdrawalRequest());
        bytes memory err =
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this));
        vm.expectRevert(err);
        withdrawals721.upgradeToAndCall(newImpl, "");
    }

    function test_upgrade_FailsIfNotUUPS() public {
        // MockERC20 is not UUPS
        address newImpl = address(new MockERC20());
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, newImpl));
        withdrawals721.upgradeToAndCall(newImpl, "");
    }

    function test_upgrade() public {
        address newImpl = address(new WBERAStakerVaultWithdrawalRequest());
        vm.prank(governance);
        withdrawals721.upgradeToAndCall(newImpl, "");
        // verify that the implementation was upgraded
        address implSet = address(uint160(uint256(vm.load(address(withdrawals721), ERC1967Utils.IMPLEMENTATION_SLOT))));
        assertEq(implSet, newImpl);
    }

    function test_setWBERAStakerVault_FailIfNotOwner() public {
        bytes memory err =
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this));
        vm.expectRevert(err);
        withdrawals721.setWBERAStakerVault(address(0));
    }

    function test_setWBERAStakerVault_FailIfZero() public {
        vm.startPrank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        withdrawals721.setWBERAStakerVault(address(0));
    }

    function test_setWBERAStakerVault() public {
        address newStakerVault = makeAddr("newStakerVault");
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVaultWithdrawalRequest.WBERAStakerVaultUpdated(stakerVault, newStakerVault);

        vm.startPrank(governance);
        withdrawals721.setWBERAStakerVault(newStakerVault);
    }

    function test_transferFrom_AlwaysReverts() public {
        vm.expectRevert(IPOLErrors.NonTransferable.selector);
        withdrawals721.transferFrom(owner, receiver, 0);
    }

    function test_mint_FailIfNotVault() public {
        uint256 assets = 100e18;
        uint256 shares = 100e18;

        vm.expectRevert(IPOLErrors.NotWBERAStakerVault.selector);
        withdrawals721.mint(caller, receiver, owner, assets, shares);
    }

    function test_mint() public {
        uint256 assets = 100e18;
        uint256 shares = 100e18;

        vm.prank(stakerVault);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVaultWithdrawalRequest.WithdrawalRequestCreated(0);
        uint256 requestId = withdrawals721.mint(caller, receiver, owner, assets, shares);

        assertEq(withdrawals721.balanceOf(caller), 1);
        assertEq(withdrawals721.ownerOf(requestId), caller);

        _assertWithdrawalRequest(requestId, assets, shares, block.timestamp, owner, receiver);
    }

    function test_burn_FailIfNotVault() public {
        test_mint();
        uint256 requestId = 0;

        vm.expectRevert(IPOLErrors.NotWBERAStakerVault.selector);
        withdrawals721.burn(requestId);
    }

    function test_burn_FailIfNotReady() public {
        test_mint();
        uint256 requestId = 0;

        vm.expectRevert(IPOLErrors.WithdrawalNotReady.selector);
        vm.prank(stakerVault);
        withdrawals721.burn(requestId);
    }

    function test_burn() public {
        test_mint();
        uint256 requestId = 0;
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN);

        vm.prank(stakerVault);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVaultWithdrawalRequest.WithdrawalRequestCompleted(requestId);
        withdrawals721.burn(requestId);
        // verify that the request was burnt
        assertEq(withdrawals721.balanceOf(caller), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        IERC721(address(withdrawals721)).ownerOf(requestId);
    }

    function test_cancel_FailsIfNotVault() public {
        test_mint();
        uint256 requestId = 0;
        vm.expectRevert(IPOLErrors.NotWBERAStakerVault.selector);
        withdrawals721.cancel(requestId);
    }

    function test_cancel() public {
        test_mint();
        uint256 requestId = 0;
        vm.prank(stakerVault);
        vm.expectEmit(true, true, true, true);
        emit IWBERAStakerVaultWithdrawalRequest.WithdrawalRequestCancelled(requestId);
        withdrawals721.cancel(requestId);
        // verify that the request was cancelled
        assertEq(withdrawals721.balanceOf(caller), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, requestId));
        IERC721(address(withdrawals721)).ownerOf(requestId);
    }

    function test_getRequest_ReturnEmptyRequestIfTokenNotExists() public view {
        uint256 requestId = 0;
        WBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawals721.getRequest(requestId);
        assertEq(request.assets, 0);
        assertEq(request.shares, 0);
        assertEq(request.requestTime, 0);
        assertEq(request.receiver, address(0));
        assertEq(request.owner, address(0));
    }

    function test_getRequest() public {
        test_mint();
        uint256 requestId = 0;

        WBERAStakerVaultWithdrawalRequest.WithdrawalRequest memory request = withdrawals721.getRequest(requestId);

        assertEq(request.assets, 100e18);
        assertEq(request.shares, 100e18);
        assertEq(request.requestTime, block.timestamp);
        assertEq(request.receiver, receiver);
        assertEq(request.owner, owner);
    }
}
