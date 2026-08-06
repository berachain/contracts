// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LibClone } from "solady/src/utils/LibClone.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { HoneyBaseTest, CollateralVault } from "./HoneyBase.t.sol";

contract CollateralVaultTest is HoneyBaseTest {
    function test_vaultParams() external {
        assertEq(daiVault.name(), "MockDAIVault");
        assertEq(daiVault.symbol(), "DAIVault");
        assertEq(daiVault.asset(), address(dai));
        assertEq(daiVault.factory(), address(factory));
    }

    function test_initializeVault_failsIfZeroFactory() external {
        address beacon = factory.beacon();
        // deploy new beacon proxy
        bytes32 salt = keccak256(abi.encode(address(dai)));
        CollateralVault newDaiVault = CollateralVault(LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt));
        // revert if initialized with zero factory address.
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newDaiVault.initialize(address(dai), address(0));
    }

    function test_initializeVault_failsIfZeroAsset() external {
        address beacon = factory.beacon();
        // deploy new beacon proxy
        bytes32 salt = keccak256(abi.encode(address(0)));
        CollateralVault zeroAddrVault = CollateralVault(LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt));
        // revert with EvmError.
        vm.expectRevert(bytes(""));
        zeroAddrVault.initialize(address(0), address(factory));
    }

    function test_pausingVault_failsIfNotFactory() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.pause();
    }

    function test_pauseVault_succeedsWithCorrectSender() external {
        vm.prank(address(factory));
        daiVault.pause();
        assertEq(daiVault.paused(), true);
    }

    function test_unpausingVault_failsIfNotFactory() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.unpause();
    }

    function test_unpausingVault_succeedsWithCorrectSender() external {
        vm.startPrank(address(factory));
        daiVault.pause();
        daiVault.unpause();
        assertEq(daiVault.paused(), false);
    }

    function test_deposit_withOutOwner() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        uint256 daiToMint = 100e18;
        daiVault.deposit(daiToMint, address(this));
    }

    function test_deposit_whileItsPaused() external {
        uint256 daiToMint = 100e18;
        vm.prank(address(factory));
        daiVault.pause();

        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        daiVault.deposit(daiToMint, address(this));
    }

    function testFuzz_deposit_succeedsWithCorrectSender(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        dai.transfer(address(factory), _daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), _daiToMint);
        daiVault.deposit(_daiToMint, address(this));
        uint256 shares = daiVault.balanceOf(address(this));

        assertEq(shares, _daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), _daiToMint);
        assertEq(dai.balanceOf(address(this)), daiBalance - _daiToMint);
    }

    function testFuzz_depositIntoUSTVault(uint256 _usdtToMint) external {
        _usdtToMint = _bound(_usdtToMint, 0, usdtBalance);
        uint256 honeyOverUsdtRate = 1e12;
        usdt.transfer(address(factory), _usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), _usdtToMint);
        usdtVault.deposit(_usdtToMint, address(this));
        uint256 shares = usdtVault.balanceOf(address(this));

        assertEq(shares, _usdtToMint * honeyOverUsdtRate);
        assertEq(usdt.balanceOf(address(usdtVault)), _usdtToMint);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - _usdtToMint);
    }

    function test_deposit() external {
        uint256 daiToMint = 100e18;
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.deposit(daiToMint, address(this));
        uint256 shares = daiVault.balanceOf(address(this));

        assertEq(shares, daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), daiToMint);
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
    }

    function test_mint_failsWithIncorrectSender() external {
        uint256 daiToMint = 100e18;
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.mint(daiToMint, receiver);
    }

    function test_mint_whileItsPaused() external {
        uint256 daiToMint = 100e18;
        vm.prank(address(factory));
        daiVault.pause();

        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        daiVault.mint(daiToMint, address(this));
    }

    function testFuzz_mint_succeedsWithCorrectSender(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 honeySupplyBefore = honey.totalSupply();
        dai.transfer(address(factory), _daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), _daiToMint);
        daiVault.mint(_daiToMint, receiver);

        assertEq(honey.totalSupply(), honeySupplyBefore); //No Honey will be minted
        assertEq(daiVault.balanceOf(receiver), _daiToMint);
        assertEq(daiVault.balanceOf(feeReceiver), 0);
    }

    function testFuzz_mintFromUSTVault(uint256 _usdtToMint) external {
        _usdtToMint = _bound(_usdtToMint, 0, usdtBalance);
        uint256 honeyOverUsdtRate = 1e12;
        usdt.transfer(address(factory), _usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), _usdtToMint);
        //shares amount is passed as the input for mint function
        usdtVault.mint(_usdtToMint * honeyOverUsdtRate, receiver);
        uint256 shares = usdtVault.balanceOf(receiver);

        assertEq(shares, _usdtToMint * honeyOverUsdtRate);
        assertEq(usdt.balanceOf(address(usdtVault)), _usdtToMint);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - _usdtToMint);
    }

    function test_mint() external {
        uint256 daiToMint = 100e18;
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, receiver);

        assertEq(daiVault.balanceOf(receiver), daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), daiToMint);
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
    }

    function testFuzz_withdraw_failsWithIncorrectSender(uint128 _daiToWithdraw) external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.withdraw(_daiToWithdraw, receiver, receiver);
    }

    function testFuzz_withdraw_failsWithInsufficientBalance(uint256 _daiToWithdraw) external {
        _daiToWithdraw = _bound(_daiToWithdraw, 1, type(uint256).max);
        vm.prank(address(factory));
        vm.expectRevert(ERC4626.WithdrawMoreThanMax.selector);
        //receiver does not have enough shares to withdraw
        daiVault.withdraw(_daiToWithdraw, receiver, receiver);
    }

    function test_withdraw_whileItsPaused() external {
        uint256 redeemedDai = 100e18;
        vm.prank(address(factory));
        daiVault.pause();

        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        daiVault.withdraw(redeemedDai, address(this), address(this));
    }

    function testFuzz_withdraw_failsWithInsufficientAllowance(uint256 _daiToWithdraw) external {
        uint256 daiToMint = 100e18;
        _daiToWithdraw = _bound(_daiToWithdraw, 1, daiToMint);
        dai.transfer(address(factory), daiToMint);

        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, receiver);

        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        daiVault.withdraw(_daiToWithdraw, receiver, receiver);
    }

    function testFuzz_withdraw_succeedsWithCorrectSender(uint256 _daiToWithdraw) external {
        uint256 daiToMint = 100e18;
        _daiToWithdraw = _bound(_daiToWithdraw, 0, daiToMint);
        dai.transfer(address(factory), daiToMint);

        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, address(factory));
        uint256 shares = daiVault.balanceOf(address(factory));

        assertEq(shares, daiToMint);
        daiVault.withdraw(_daiToWithdraw, receiver, address(factory));

        uint256 sharesAfter = daiVault.balanceOf(address(factory));
        assertEq(sharesAfter, daiToMint - _daiToWithdraw);
        assertEq(dai.balanceOf(receiver), _daiToWithdraw);
    }

    function testFuzz_withdrawFromUSTVault(uint256 _usdtToWithdraw) external {
        uint256 usdtToMint = 100e6;
        uint256 honeyOverUsdtRate = 1e12;
        _usdtToWithdraw = _bound(_usdtToWithdraw, 0, usdtToMint);
        usdt.transfer(address(factory), usdtToMint);

        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), usdtToMint);
        usdtVault.deposit(usdtToMint, address(factory));
        uint256 shares = usdtVault.balanceOf(address(factory));

        assertEq(shares, usdtToMint * honeyOverUsdtRate);

        usdtVault.withdraw(_usdtToWithdraw, receiver, address(factory));
        uint256 sharesAfter = usdtVault.balanceOf(address(factory));
        assertEq(sharesAfter, usdtToMint * honeyOverUsdtRate - _usdtToWithdraw * honeyOverUsdtRate);
        assertEq(usdt.balanceOf(receiver), _usdtToWithdraw);
    }

    function test_withdraw() external {
        uint256 redeemedDai = 100e18;
        dai.transfer(address(factory), redeemedDai);

        vm.startPrank(address(factory));
        dai.approve(address(daiVault), redeemedDai);
        daiVault.mint(redeemedDai, address(factory));
        uint256 shares = daiVault.balanceOf(address(factory));

        assertEq(shares, redeemedDai);
        daiVault.withdraw(redeemedDai, receiver, address(factory));

        uint256 sharesAfter = daiVault.balanceOf(address(factory));
        assertEq(sharesAfter, 0);
        assertEq(dai.balanceOf(receiver), redeemedDai);
    }

    function test_redeem_withOutOwner() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        uint256 redeemedDai = 100e18;
        daiVault.redeem(redeemedDai, address(this), address(this));
    }

    function test_redeem_whileItsPaused() external {
        uint256 redeemedDai = 100e18;
        vm.prank(address(factory));
        daiVault.pause();

        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultPaused.selector, address(dai)));
        daiVault.redeem(redeemedDai, address(this), address(this));
    }

    function testFuzz_redeem_failsWithInsufficientBalance(uint256 _redeemedDai) external {
        _redeemedDai = _bound(_redeemedDai, 1, type(uint256).max);
        vm.prank(address(factory));
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        //receiver does not have enough shares to redeem
        daiVault.redeem(_redeemedDai, receiver, receiver);
    }

    function testFuzz_redeem_failWithInsufficientAllowance(uint256 _redeemedDai) external {
        uint256 daiToMint = 100e18;
        _redeemedDai = _bound(_redeemedDai, 1, daiToMint);
        dai.transfer(address(factory), daiToMint);

        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, receiver);

        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        daiVault.redeem(_redeemedDai, receiver, receiver);
    }

    function testFuzz_redeem_succeedsWithCorrectSender(uint256 _redeemedDai) external {
        uint256 daiToMint = 100e18;
        _redeemedDai = _bound(_redeemedDai, 0, daiToMint);
        dai.transfer(address(factory), daiToMint);

        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, address(factory));
        uint256 shares = daiVault.balanceOf(address(factory));
        assertEq(shares, daiToMint);

        daiVault.redeem(_redeemedDai, receiver, address(factory));
        uint256 sharesAfter = daiVault.balanceOf(address(factory));

        assertEq(sharesAfter, daiToMint - _redeemedDai);
        assertEq(dai.balanceOf(receiver), _redeemedDai);
    }

    function testFuzz_redeemFromUSTVault(uint256 _redeemedUsdt) external {
        uint256 usdtToMint = 100e6;
        uint256 honeyOverUsdtRate = 1e12;
        _redeemedUsdt = _bound(_redeemedUsdt, 0, usdtToMint);
        usdt.transfer(address(factory), usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), usdtToMint);
        usdtVault.deposit(usdtToMint, address(factory));
        uint256 shareBalance = usdtVault.balanceOf(address(factory));
        assertEq(shareBalance, usdtToMint * honeyOverUsdtRate);

        //redeem function takes shares as input
        uint256 sharesToRedeem = _redeemedUsdt * honeyOverUsdtRate;
        usdtVault.redeem(sharesToRedeem, receiver, address(factory));

        uint256 sharesAfter = usdtVault.balanceOf(address(factory));
        assertEq(sharesAfter, usdtToMint * honeyOverUsdtRate - _redeemedUsdt * honeyOverUsdtRate);
        assertEq(usdt.balanceOf(receiver), _redeemedUsdt);
    }

    function test_redeem() external {
        uint256 redeemedDai = 100e18;
        dai.transfer(address(factory), redeemedDai);

        vm.startPrank(address(factory));
        dai.approve(address(daiVault), redeemedDai);
        daiVault.deposit(redeemedDai, (address(factory)));

        uint256 shares = daiVault.balanceOf(address(factory));
        assertEq(shares, redeemedDai);

        daiVault.redeem(redeemedDai, receiver, address(factory));

        uint256 sharesAfter = daiVault.balanceOf(address(factory));
        assertEq(sharesAfter, 0);
        assertEq(dai.balanceOf(receiver), redeemedDai);
    }

    function test_Deposit_InCustody() external {
        // generate custody address and give infinite allowance to usdtVault
        address custody = getCustodyAndSetAllowanceToVault();

        // deposit some usdt in the vault
        usdt.transfer(address(factory), 1000e6);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), 1000e6);
        usdtVault.deposit(100e6, address(factory));
        assertEq(usdt.balanceOf(address(usdtVault)), 100e6);

        // when custody is set, all usdtVault usdt moves to the custody address
        usdtVault.setCustodyInfo(true, custody);
        assertEq(usdt.balanceOf(address(usdtVault)), 0);
        assertEq(usdt.balanceOf(custody), 100e6);

        // test deposit in custody
        usdtVault.deposit(100e6, address(factory));
        assertEq(usdt.balanceOf(address(usdtVault)), 0);
        assertEq(usdt.balanceOf(custody), 200e6);

        // when custody is removed, all usdt moves back to the usdtVault
        usdtVault.setCustodyInfo(false, address(custody));
        assertEq(usdt.balanceOf(address(usdtVault)), 200e6);
        assertEq(usdt.balanceOf(custody), 0);
    }

    function test_Mint_inCustody() external {
        // generate custody address and give infinite allowance to usdtVault
        address custody = getCustodyAndSetAllowanceToVault();

        usdt.transfer(address(factory), 1000e6);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), 1000e6);

        // set the custody vault
        usdtVault.setCustodyInfo(true, custody);

        // mint 100e18 share of vault, which means 100e6 usdt required
        usdtVault.mint(100e18, address(factory));
        assertEq(usdt.balanceOf(address(usdtVault)), 0);
        assertEq(usdt.balanceOf(custody), 100e6);

        // mint more shares
        usdtVault.mint(100e18, address(factory));
        assertEq(usdt.balanceOf(address(usdtVault)), 0);
        assertEq(usdt.balanceOf(custody), 200e6);

        // when custody is removed, all usdt moves back to the usdtVault
        usdtVault.setCustodyInfo(false, address(custody));
        assertEq(usdt.balanceOf(address(usdtVault)), 200e6);
        assertEq(usdt.balanceOf(custody), 0);
    }

    function test_redeem_inCustody() external {
        // generate custody address and give infinite allowance to usdtVault
        address custody = getCustodyAndSetAllowanceToVault();
        usdt.transfer(address(factory), 1000e6);

        // set the custody vault
        vm.startPrank(address(factory));
        usdtVault.setCustodyInfo(true, custody);

        usdt.approve(address(usdtVault), 1000e6);
        usdtVault.deposit(100e6, address(factory));
        assertEq(usdt.balanceOf(address(usdtVault)), 0);
        assertEq(usdt.balanceOf(custody), 100e6);

        // redeem from custody
        uint256 sharesToRedeem = 50e6 * 1e12;
        usdtVault.redeem(sharesToRedeem, address(factory), address(factory));
        assertEq(usdt.balanceOf(address(usdtVault)), 0);
        assertEq(usdt.balanceOf(custody), 50e6);

        // redeem more than the custody balance
        sharesToRedeem = 100e6 * 1e12;
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        usdtVault.redeem(sharesToRedeem, address(factory), address(factory));
    }

    function test_setCustodyInfo() external {
        // generate custody address and give infinite allowance to usdtVault
        address custody = getCustodyAndSetAllowanceToVault();

        // should revert if set custody vault with zero address
        vm.prank(address(factory));
        vm.expectRevert(IHoneyErrors.ZeroAddress.selector);
        usdtVault.setCustodyInfo(true, address(0));

        // should set custody vault successfully
        vm.prank(address(factory));
        vm.expectEmit(true, true, true, true);
        emit CollateralVault.CustodyInfoSet(true, custody);
        usdtVault.setCustodyInfo(true, custody);
        (bool isCustodyVault, address custodyAddress) = usdtVault.custodyInfo();
        assertEq(isCustodyVault, true);
        assertEq(custodyAddress, custody);

        // should revert if try to change custody vault without removing the existing custody vault
        vm.prank(address(factory));
        vm.expectRevert(IHoneyErrors.InvalidCustodyInfoInput.selector);
        usdtVault.setCustodyInfo(true, address(factory));

        // should revert if try to remove custody vault without passing existing custody vault address
        vm.prank(address(factory));
        vm.expectRevert(IHoneyErrors.InvalidCustodyInfoInput.selector);
        usdtVault.setCustodyInfo(false, address(factory));

        // should remove custody vault successfully
        vm.prank(address(factory));
        vm.expectEmit(true, true, true, true);
        emit CollateralVault.CustodyInfoSet(false, address(0));
        usdtVault.setCustodyInfo(false, custody);
        (isCustodyVault, custodyAddress) = usdtVault.custodyInfo();
        assertEq(isCustodyVault, false);
        assertEq(custodyAddress, address(0));
    }

    function getCustodyAndSetAllowanceToVault() internal returns (address custody) {
        custody = makeAddr("custody");
        vm.prank(custody);
        usdt.approve(address(usdtVault), type(uint256).max);
        return custody;
    }
}
