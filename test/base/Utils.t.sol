// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { MissingReturnToken } from "solady/test/utils/weird-tokens/MissingReturnToken.sol";
import { RevertingToken } from "solady/test/utils/weird-tokens/RevertingToken.sol";
import { ReturnsFalseToken } from "solady/test/utils/weird-tokens/ReturnsFalseToken.sol";
import { ReturnsTwoToken } from "solady/test/utils/weird-tokens/ReturnsTwoToken.sol";

import { Utils } from "src/libraries/Utils.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";
import { MaxGasConsumeERC20 } from "@mock/token/MaxGasConsumeERC20.sol";

contract UtilsTest is Test {
    using Utils for address;

    address internal _spender = makeAddr("spender");
    MockERC20 internal _token;

    MissingReturnToken internal _missingReturnToken;
    RevertingToken internal _revertingToken;
    ReturnsFalseToken internal _returnFalseToken;
    ReturnsTwoToken internal _returnTwoToken;
    MaxGasConsumeERC20 internal _exeedGasLimitToken;

    function setUp() public {
        _token = new MockERC20();
        _token.initialize("MockToken", "MTK");

        _missingReturnToken = new MissingReturnToken();
        _revertingToken = new RevertingToken();
        _returnFalseToken = new ReturnsFalseToken();
        _returnTwoToken = new ReturnsTwoToken();
        _exeedGasLimitToken = new MaxGasConsumeERC20();
    }

    function test_Allowance() public {
        testFuzz_Allowance(address(this), _spender, 1e18);
    }

    function testFuzz_Allowance(address admin, address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        vm.assume(admin != address(0));
        vm.prank(admin);
        _token.approve(spender, amount);
        uint256 allowanceViaUtils = Utils.allowance(address(_token), admin, spender);
        assertEq(_token.allowance(admin, spender), amount);
        assertEq(allowanceViaUtils, amount);
    }

    function test_Allowance_WhenTokenNotExists() public view {
        // address(this) is not a token
        uint256 allowanceViaUtils = Utils.allowance(address(this), address(this), _spender);
        assertEq(allowanceViaUtils, 0);
    }

    function _safeIncreaseAllowance(address token, address spender, uint256 amount) public {
        token.safeIncreaseAllowance(spender, amount);
    }

    function test_SafeIncreaseAllowance_IfTokenNotExists() public {
        address nonExistentToken = makeAddr("nonExistentToken");
        vm.expectRevert(SafeTransferLib.ApproveFailed.selector);
        // wrapping the call in a function to avoid test failure after solady upgrade
        this._safeIncreaseAllowance(nonExistentToken, _spender, 1e18);
    }

    function testFuzz_SafeIncreaseAllowance_Overflow(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0);
        amount1 = _bound(amount1, type(uint256).max - amount0 + 1, type(uint256).max);
        address(_token).safeIncreaseAllowance(_spender, amount0);
        vm.expectRevert(Utils.IncreaseAllowanceOverflow.selector);
        address(_token).safeIncreaseAllowance(_spender, amount1);
    }

    function test_SafeIncreaseAllowance() public {
        testFuzz_SafeIncreaseAllowance(_spender, 1e18);
    }

    function testFuzz_SafeIncreaseAllowance(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        // approve some initial amount
        SafeTransferLib.safeApprove(address(_token), spender, 1e18);
        amount = _bound(amount, 1, type(uint256).max - 1e18);
        // increase allowance by amount
        address(_token).safeIncreaseAllowance(spender, amount);
        uint256 allowanceViaUtils = Utils.allowance(address(_token), address(this), spender);
        assertEq(_token.allowance(address(this), spender), amount + 1e18);
        assertEq(allowanceViaUtils, amount + 1e18);
    }

    function testFuzz_TrySafeTransferERC20(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        _token.mint(address(this), amount);
        uint256 prBl = _token.balanceOf(address(this));
        assertEq(prBl, amount);

        bool success = address(_token).trySafeTransfer(to, amount);
        assertTrue(success);

        assertEq(_token.balanceOf(address(this)), prBl - amount);
        assertEq(_token.balanceOf(to), amount);
    }

    function testFuzz_TrySafeTransferMissingReturnToken(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        uint256 prBl = _missingReturnToken.balanceOf(address(this));

        bool success = address(_missingReturnToken).trySafeTransfer(to, amount);
        assertTrue(success);

        assertEq(_missingReturnToken.balanceOf(address(this)), prBl - amount);
        assertEq(_missingReturnToken.balanceOf(to), amount);
    }

    function testFuzz_TrySafeTransferRevertingToken(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        uint256 prBl = _revertingToken.balanceOf(address(this));

        bool success = address(_revertingToken).trySafeTransfer(to, amount);
        assertFalse(success);
        assertEq(_revertingToken.balanceOf(address(this)), prBl);
        assertEq(_revertingToken.balanceOf(to), 0);
    }

    function testFuzz_TrySafeTransferReturnFalseToken(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        uint256 prBl = _returnFalseToken.balanceOf(address(this));

        bool success = address(_returnFalseToken).trySafeTransfer(to, amount);
        assertFalse(success);
        assertEq(_returnFalseToken.balanceOf(address(this)), prBl);
        assertEq(_returnFalseToken.balanceOf(to), 0);
    }

    function testFuzz_TrySafeTransferReturnTwoToken(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        uint256 prBl = _returnTwoToken.balanceOf(address(this));

        bool success = address(_returnTwoToken).trySafeTransfer(to, amount);
        assertFalse(success);
        assertEq(_returnTwoToken.balanceOf(address(this)), prBl);
        assertEq(_returnTwoToken.balanceOf(to), 0);
    }

    function testFuzz_TrySafeTransferDoesNotExeedGasLimit(address to) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        _exeedGasLimitToken.setLoopCount(1e3);
        _exeedGasLimitToken.mint(address(this), 2e18);

        uint256 gas = gasleft();
        _exeedGasLimitToken.transfer(to, 1e18);
        uint256 gasUsed = gas - gasleft();
        assertLt(gasUsed, 5e5); // Check used for the transfer is lower than the limit (500k)

        bool success = address(_exeedGasLimitToken).trySafeTransfer(address(this), 1e18);
        assertTrue(success);
    }

    function testFuzz_TrySafeTransferExeedGasLimit(address to) public {
        vm.assume(to != address(0));
        vm.assume(to != address(this));

        _exeedGasLimitToken.setLoopCount(1e4);
        _exeedGasLimitToken.mint(address(this), 2e18);

        uint256 gas = gasleft();
        _exeedGasLimitToken.transfer(to, 1e18);
        uint256 gasUsed = gas - gasleft();
        assertGt(gasUsed, 5e5); // Check used for the transfer is greater than the limit (500k)

        bool success = address(_exeedGasLimitToken).trySafeTransfer(address(this), 1e18);
        assertFalse(success);
    }
}
