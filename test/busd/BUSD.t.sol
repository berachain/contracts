// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable } from "solady/src/auth/Ownable.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { SoladyTest } from "solady/test/utils/SoladyTest.sol";

import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IBUSDErrors } from "src/busd/IBUSDErrors.sol";
import { BUSD, EIP3009 } from "src/busd/BUSD.sol";
import { BUSDDeployer } from "src/busd/BUSDDeployer.sol";
import { BUSDFactory } from "src/busd/BUSDFactory.sol";
import { MockBUSD, FaultyMockBUSD } from "@mock/busd/MockBUSD.sol";
import { MockOracle } from "@mock/oracle/MockOracle.sol";
import { Salt } from "src/base/Salt.sol";

contract BUSDTest is StdCheats, SoladyTest {
    struct _TestTemps {
        address owner;
        address to;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 privateKey;
        uint256 nonce;
    }

    struct _TestEIP3009 {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        uint256 privateKey;
        bytes32 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    address internal governance = makeAddr("governance");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal polFeeCollector = makeAddr("polFeeCollector");
    // address used to test transfer and transferFrom
    address internal spender = makeAddr("spender");
    BUSD internal busd;
    BUSDDeployer internal deployer;
    BUSDFactory internal factory;

    Salt internal _busdSalt = Salt({ implementation: 0, proxy: 0 });
    Salt internal _busdFactorySalt = Salt({ implementation: 0, proxy: 1 });
    Salt internal _busdFactoryReaderSalt = Salt({ implementation: 0, proxy: 1 });

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        MockOracle oracle = new MockOracle();
        deployer = new BUSDDeployer(
            governance,
            feeReceiver,
            polFeeCollector,
            _busdSalt,
            _busdFactorySalt,
            _busdFactoryReaderSalt,
            address(oracle)
        );
        busd = deployer.busd();
        factory = deployer.busdFactory();
        assertEq(busd.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance), true);

        // verify the version is "1"
        assertEq(busd.version(), "1");
        // initialize the contract with the v2 update
        busd.initializeV1Update();
        // verify the EIP712 domain separator version is "1"
        assertEq(busd.version(), "1");
    }

    function test_Initialize_FailsIfZeroAddresses() public {
        BUSD newBUSD = BUSD(LibClone.deployERC1967(address(new BUSD())));

        // initialize with zero address governance
        vm.expectRevert(abi.encodeWithSelector(IBUSDErrors.ZeroAddress.selector));
        newBUSD.initialize(address(0), address(factory));

        // initialize with zero address factory
        vm.expectRevert(abi.encodeWithSelector(IBUSDErrors.ZeroAddress.selector));
        newBUSD.initialize(governance, address(0));
    }

    function test_MetaData() public {
        assertEq(busd.name(), "Bera USD");
        assertEq(busd.symbol(), "BUSD");
        assertEq(busd.decimals(), 18);
    }

    /// @dev Test that minting BUSD fails if the caller is not the factory.
    function test_Mint_FailIfNotFactory() public {
        vm.expectRevert(IBUSDErrors.NotFactory.selector);
        busd.mint(address(this), 100);
    }

    /// @dev Test that minting BUSD fails if the total supply overflows.
    function testFuzz_Mint_TotalSupplyOverflow(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0);
        amount1 = _bound(amount1, type(uint256).max - amount0 + 1, type(uint256).max);

        vm.startPrank(address(factory));
        busd.mint(address(this), amount0);

        vm.expectRevert(ERC20.TotalSupplyOverflow.selector);
        busd.mint(address(this), amount1);
    }

    /// @dev Test minting BUSD
    function test_Mint() public {
        testFuzz_Mint(100e18);
    }

    /// @dev Test minting BUSD
    function testFuzz_Mint(uint256 mintAmount) public {
        uint256 totalSupplyPre = busd.totalSupply();
        uint256 balancePre = busd.balanceOf(address(this));

        vm.expectEmit();
        emit ERC20.Transfer(address(0), address(this), mintAmount);
        _mint(mintAmount);

        uint256 totalSupplyPost = busd.totalSupply();
        uint256 balancePost = busd.balanceOf(address(this));
        assertEq(totalSupplyPost, totalSupplyPre + mintAmount);
        assertEq(balancePost, balancePre + mintAmount);
    }

    /// @dev Test that burning BUSD fails if the caller is not the factory.
    function test_Burn_FailIfNotFactory() public {
        vm.expectRevert(IBUSDErrors.NotFactory.selector);
        busd.burn(address(this), 100);
    }

    /// @dev Test that burning BUSD fails if there is insufficient balance.
    function test_Burn_FailIfInsufficientBalance() public {
        testFuzz_Burn_FailIfInsufficientBalance(0, 50);
    }

    /// @dev Test that burning BUSD fails if there is insufficient balance.
    function testFuzz_Burn_FailIfInsufficientBalance(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(burnAmount > 0);
        mintAmount = _bound(mintAmount, 0, burnAmount - 1);
        _mint(mintAmount);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        vm.prank(address(factory));
        busd.burn(address(this), burnAmount);
    }

    /// @dev Test burning BUSD
    function test_Burn() public {
        testFuzz_Burn(100, 50);
    }

    /// @dev Test burning BUSD
    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0);
        burnAmount = _bound(burnAmount, 0, mintAmount);
        _mint(mintAmount);

        vm.expectEmit();
        emit ERC20.Transfer(address(this), address(0), burnAmount);
        vm.prank(address(factory));
        busd.burn(address(this), burnAmount);

        assertEq(busd.balanceOf(address(this)), mintAmount - burnAmount);
        assertEq(busd.totalSupply(), mintAmount - burnAmount);
    }

    function test_Approve() public {
        testFuzz_Approve(spender, 1e18);
    }

    function testFuzz_Approve(address _spender, uint256 amount) public {
        vm.expectEmit();
        emit ERC20.Approval(address(this), _spender, amount);
        bool approveSuccess = busd.approve(_spender, amount);
        uint256 allowance = busd.allowance(address(this), _spender);

        assertTrue(approveSuccess);
        assertEq(allowance, amount);
    }

    function test_Transfer_FailsIfInsufficientBalance() public {
        testFuzz_Transfer_FailsIfInsufficientBalance(governance, 2e18);
    }

    function testFuzz_Transfer_FailsIfInsufficientBalance(address to, uint256 amount) public {
        _mint(1e18);
        amount = _bound(amount, 1e18 + 1, type(uint256).max);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        busd.transfer(to, amount);
    }

    function test_Transfer() public {
        testFuzz_Transfer(governance, 1e18);
    }

    function testFuzz_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(this));
        _mint(amount);

        vm.expectEmit();
        emit ERC20.Transfer(address(this), to, amount);
        bool transferSuccess = busd.transfer(to, amount);

        assertTrue(transferSuccess);
        assertEq(busd.totalSupply(), amount);
        assertEq(busd.balanceOf(address(this)), 0);
        assertEq(busd.balanceOf(to), amount);
    }

    function test_TransferFrom_FailsIfInsufficientAllowance() public {
        testFuzz_TransferFrom_FailsIfInsufficientAllowance(governance, 1e18);
    }

    function testFuzz_TransferFrom_FailsIfInsufficientAllowance(address to, uint256 amount) public {
        vm.assume(amount > 0);
        _mint(amount);
        // address(this) approves randomCaller to spend (amount - 1) BUSD.
        busd.approve(spender, amount - 1);

        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        busd.transferFrom(address(this), to, amount);
    }

    function test_TransferFrom_FailsIfInsufficientBalance() public {
        testFuzz_TransferFrom_FailsIfInsufficientBalance(governance, 1e18);
    }

    function testFuzz_TransferFrom_FailsIfInsufficientBalance(address to, uint256 amount) public {
        vm.assume(amount > 0);
        _mint(amount - 1);
        // address(this) approves spender to spend amount BUSD.
        busd.approve(spender, amount);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        busd.transferFrom(address(this), to, amount);
    }

    function test_TransferFrom() public {
        testFuzz_TransferFrom(governance, 1e18);
    }

    function testFuzz_TransferFrom(address to, uint256 amount) public {
        vm.assume(to != address(this));
        _mint(amount);
        // address(this) approves randomCaller to spend amount BUSD.
        busd.approve(spender, amount);
        vm.expectEmit();
        emit ERC20.Transfer(address(this), to, amount);
        vm.prank(spender);
        bool transferSuccess = busd.transferFrom(address(this), to, amount);

        assertTrue(transferSuccess);
        assertEq(busd.totalSupply(), amount);
        assertEq(busd.balanceOf(address(this)), 0);
        assertEq(busd.balanceOf(to), amount);
    }

    function test_Permit() public {
        _TestTemps memory t = _testTemps();
        t.deadline = block.timestamp;

        _signPermit(t);

        _expectPermitEmitApproval(t);
        _permit(t);

        _checkAllowanceAndNonce(t);
    }

    function test_Permit_BadNonceReverts() public {
        _TestTemps memory t = _testTemps();
        if (t.deadline < block.timestamp) t.deadline = block.timestamp;
        while (t.nonce == 0) t.nonce = _random();

        _signPermit(t);

        vm.expectRevert(ERC20.InvalidPermit.selector);
        _permit(t);
    }

    function test_Permit_BadDeadlineReverts() public {
        _TestTemps memory t = _testTemps();
        if (t.deadline == type(uint256).max) t.deadline--;
        if (t.deadline < block.timestamp) t.deadline = block.timestamp;

        _signPermit(t);

        vm.expectRevert(ERC20.InvalidPermit.selector);
        t.deadline += 1;
        _permit(t);
    }

    function test_Permit_PastDeadlineReverts() public {
        _TestTemps memory t = _testTemps();
        t.deadline = _bound(t.deadline, 0, block.timestamp - 1);

        _signPermit(t);

        vm.expectRevert(ERC20.PermitExpired.selector);
        _permit(t);
    }

    function test_Permit_ReplayReverts() public {
        _TestTemps memory t = _testTemps();
        if (t.deadline < block.timestamp) t.deadline = block.timestamp;

        _signPermit(t);

        _expectPermitEmitApproval(t);
        _permit(t);
        vm.expectRevert(ERC20.InvalidPermit.selector);
        _permit(t);
    }

    function test_UpgradeTo_FailIfNotOwner() public {
        testFuzz_UpgradeTo_FailsIfNotOwner(address(this));
    }

    function testFuzz_UpgradeTo_FailsIfNotOwner(address caller) public {
        address newBUSDImpl = address(new BUSD());
        vm.assume(caller != governance);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN_ROLE
            )
        );
        busd.upgradeToAndCall(newBUSDImpl, bytes(""));
    }

    function test_UpgradeToFaultyBUSD() public {
        assertEq(busd.name(), "Bera USD");
        assertEq(busd.symbol(), "BUSD");

        address busdFactory = busd.factory();

        address faultyBUSDOwner = address(0x3);
        vm.startPrank(faultyBUSDOwner);
        FaultyMockBUSD faultyBUSDImpl = new FaultyMockBUSD();
        vm.stopPrank();

        vm.expectEmit();
        emit IERC1967.Upgraded(address(faultyBUSDImpl));
        // Only governance can upgrade the contract, since it's the owner of the Proxy
        vm.prank(governance);
        busd.upgradeToAndCall(address(faultyBUSDImpl), bytes(""));

        // Initialize the faultyBUSD through the proxy
        FaultyMockBUSD(address(busd)).initialize(faultyBUSDOwner);

        // Factory slot has not initializated on the Proxy storage
        // So factory is equal to address(0)
        // "collidedFactoryValue" variable instead, has taken the value of the factory address
        // since it's pointing to the "original" factory slot of the storage
        assertNotEq(busd.factory(), busdFactory);
        assertEq(FaultyMockBUSD(address(busd)).collidedFactoryValue(), busdFactory);
        assertEq(busd.factory(), address(0x0));
    }

    function test_UpgradeTo() public {
        // mint 1 busd
        _mint(1e18);

        assertEq(busd.name(), "Bera USD");
        assertEq(busd.symbol(), "BUSD");

        // get the totalSupply and the factory address from current implementation
        uint256 busdMintedBeforeUpgrade = busd.totalSupply();
        address busdFactory = busd.factory();

        MockBUSD mockBUSDImpl = new MockBUSD();

        vm.expectEmit();
        emit IERC1967.Upgraded(address(mockBUSDImpl));
        // Only governance can upgrade the contract
        vm.prank(governance);
        busd.upgradeToAndCall(address(mockBUSDImpl), bytes(""));
        MockBUSD(address(busd)).initialize(governance);

        assertEq(busd.name(), "MockBUSD");
        assertEq(busd.symbol(), "MOCK_BUSD");
        // Check factory address and total supply
        assertEq(busd.factory(), busdFactory);
        assertEq(busd.totalSupply(), busdMintedBeforeUpgrade);
    }

    function test_UpgradeToMockBUSDGovernanceCannotUpgradeWhenOwnerOfProxyChanges() public {
        MockBUSD mockBUSDImpl = new MockBUSD();

        address mockBUSDOwner = address(0x3);
        vm.expectEmit();
        emit IERC1967.Upgraded(address(mockBUSDImpl));
        // Only governance can upgrade the contract
        vm.prank(governance);
        busd.upgradeToAndCall(address(mockBUSDImpl), bytes(""));
        MockBUSD(address(busd)).initialize(mockBUSDOwner);

        // Check governance cannot upgrade the contract because it's not the owner of the Proxy
        address newImplementation = address(new MockBUSD());
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        vm.startPrank(governance);
        busd.upgradeToAndCall(newImplementation, bytes(""));
    }

    function test_Pause() public {
        address blackhat = makeAddr("blackhat");
        vm.prank(address(factory));
        busd.mint(blackhat, 100e18);
        assertEq(false, busd.paused());

        vm.prank(governance);
        busd.setPaused(true);
        assertEq(true, busd.paused());

        address blackhatSink = makeAddr("blackhatSink");
        vm.prank(blackhat);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        busd.transfer(blackhatSink, 100e18);

        vm.prank(governance);
        busd.setPaused(false);
        assertEq(false, busd.paused());

        vm.prank(blackhat);
        busd.transfer(blackhatSink, 100e18);
        assertEq(100e18, busd.balanceOf(blackhatSink));
    }

    function test_Blacklist() public {
        address blackhat = makeAddr("blackhat");
        vm.prank(address(factory));
        busd.mint(blackhat, 100e18);
        assertEq(false, busd.isBlacklistedWallet(blackhat));

        vm.prank(governance);
        busd.setBlacklisted(blackhat, true);
        assertEq(true, busd.isBlacklistedWallet(blackhat));

        address blackhatSink = makeAddr("blackhatSink");
        vm.prank(blackhat);
        vm.expectRevert(abi.encodeWithSelector(IBUSDErrors.BlacklistedWallet.selector));
        busd.transfer(blackhatSink, 100e18);

        vm.prank(governance);
        busd.setBlacklisted(blackhat, false);
        assertEq(false, busd.isBlacklistedWallet(blackhat));

        vm.prank(blackhat);
        busd.transfer(blackhatSink, 100e18);
        assertEq(100e18, busd.balanceOf(blackhatSink));
    }

    function test_TransferWithAuthorization() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signTransferWithAuthorization(t);
        vm.expectEmit();
        emit EIP3009.AuthorizationUsed(t.from, t.nonce);
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
        // verify the balance of the from address is 0
        assertEq(busd.balanceOf(t.from), 0);
        // verify the balance of the to address is the value
        assertEq(busd.balanceOf(t.to), t.value);
        // check authorization is used
        assertEq(busd.authorizationState(t.from, t.nonce), true);
    }

    function test_TransferWithAuthorization_WithSignature() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signTransferWithAuthorization(t);
        vm.expectEmit();
        emit EIP3009.AuthorizationUsed(t.from, t.nonce);
        busd.transferWithAuthorization(
            t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, abi.encodePacked(t.r, t.s, t.v)
        );
        // verify the balance of the from address is 0
        assertEq(busd.balanceOf(t.from), 0);
        // verify the balance of the to address is the value
        assertEq(busd.balanceOf(t.to), t.value);
        // check authorization is used
        assertEq(busd.authorizationState(t.from, t.nonce), true);
    }

    function test_TransferWithAuthorization_FailsIfInvalidSignature() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signTransferWithAuthorization(t);
        t.v = 0;
        vm.expectRevert("EIP3009: invalid signature");
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_TransferWithAuthorization_FailsIfAuthorizationIsUsed() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signTransferWithAuthorization(t);
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
        vm.expectRevert("EIP3009: auth invalid");
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_TransferWithAuthorization_FailsIfAuthorizationIsExpired() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signTransferWithAuthorization(t);
        // auth will be valid before the current timestamp, if validBefore is current timestamp, it will fail.
        t.validBefore = block.timestamp;
        vm.expectRevert("EIP3009: auth expired");
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_TransferWithAuthorization_FailsIfAuthorizationIsEarly() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signTransferWithAuthorization(t);
        // auth will be valid after the current timestamp, if validAfter is current timestamp, it will fail.
        t.validAfter = block.timestamp;
        vm.expectRevert("EIP3009: auth early");
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_TransferWithAuthorization_FailsIfCancelAuthorizationIsUsed() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signCancelAuthorization(t);
        busd.cancelAuthorization(t.from, t.nonce, t.v, t.r, t.s);
        // given the authorization is canceled, it should fail to transfer with authorization.
        _signTransferWithAuthorization(t);
        vm.expectRevert("EIP3009: auth invalid");
        busd.transferWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_ReceiveWithAuthorization() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signReceiveWithAuthorization(t);
        // only payee can receive with authorization.
        vm.prank(t.to);
        vm.expectEmit();
        emit EIP3009.AuthorizationUsed(t.from, t.nonce);
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
        // verify the balance of the from address is 0
        assertEq(busd.balanceOf(t.from), 0);
        // verify the balance of the to address is the value
        assertEq(busd.balanceOf(t.to), t.value);
        // check authorization is used
        assertEq(busd.authorizationState(t.from, t.nonce), true);
    }

    function test_ReceiveWithAuthorization_WithSignature() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signReceiveWithAuthorization(t);
        vm.prank(t.to);
        vm.expectEmit();
        emit EIP3009.AuthorizationUsed(t.from, t.nonce);
        busd.receiveWithAuthorization(
            t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, abi.encodePacked(t.r, t.s, t.v)
        );
        // verify the balance of the from address is 0
        assertEq(busd.balanceOf(t.from), 0);
        // verify the balance of the to address is the value
        assertEq(busd.balanceOf(t.to), t.value);
        // check authorization is used
        assertEq(busd.authorizationState(t.from, t.nonce), true);
    }

    function test_ReceiveWithAuthorization_FailsIfCallerNotPayee() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signReceiveWithAuthorization(t);
        vm.expectRevert("EIP3009: to != msg.sender");
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_ReceiveWithAuthorization_FailsIfAuthorizationIsUsed() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signReceiveWithAuthorization(t);
        vm.startPrank(t.to);
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
        vm.expectRevert("EIP3009: auth invalid");
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
        vm.stopPrank();
    }

    function test_ReceiveWithAuthorization_FailsIfAuthorizationIsExpired() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signReceiveWithAuthorization(t);
        t.validBefore = block.timestamp;
        vm.prank(t.to);
        vm.expectRevert("EIP3009: auth expired");
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_ReceiveWithAuthorization_FailsIfAuthorizationIsEarly() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signReceiveWithAuthorization(t);
        t.validAfter = block.timestamp;
        vm.prank(t.to);
        vm.expectRevert("EIP3009: auth early");
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_ReceiveWithAuthorization_FailsIfCancelAuthorizationIsUsed() public {
        _TestEIP3009 memory t = _testEIP3009();
        // mint 1 busd to the from address
        vm.prank(address(factory));
        busd.mint(t.from, t.value);
        _signCancelAuthorization(t);
        busd.cancelAuthorization(t.from, t.nonce, t.v, t.r, t.s);
        // given the authorization is canceled, it should fail to receive with authorization.
        _signReceiveWithAuthorization(t);
        vm.prank(t.to);
        vm.expectRevert("EIP3009: auth invalid");
        busd.receiveWithAuthorization(t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce, t.v, t.r, t.s);
    }

    function test_CancelAuthorization() public {
        _TestEIP3009 memory t = _testEIP3009();
        _signCancelAuthorization(t);
        vm.expectEmit();
        emit EIP3009.AuthorizationCanceled(t.from, t.nonce);
        busd.cancelAuthorization(t.from, t.nonce, t.v, t.r, t.s);
        // check authorization is canceled
        assertEq(busd.authorizationState(t.from, t.nonce), true);
    }

    function test_CancelAuthorization_WithSignature() public {
        _TestEIP3009 memory t = _testEIP3009();
        _signCancelAuthorization(t);
        vm.expectEmit();
        emit EIP3009.AuthorizationCanceled(t.from, t.nonce);
        busd.cancelAuthorization(t.from, t.nonce, abi.encodePacked(t.r, t.s, t.v));
        // check authorization is canceled
        assertEq(busd.authorizationState(t.from, t.nonce), true);
    }

    function test_CancelAuthorization_FailsIfPaused() public {
        _TestEIP3009 memory t = _testEIP3009();
        _signCancelAuthorization(t);
        vm.prank(governance);
        busd.setPaused(true);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        busd.cancelAuthorization(t.from, t.nonce, t.v, t.r, t.s);

        // Signature input cancel authorization should also fail
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        busd.cancelAuthorization(t.from, t.nonce, abi.encodePacked(t.r, t.s, t.v));
    }

    function test_DomainSeparator_IsCorrect() public {
        // fetch domain separator from the contract
        bytes32 domainSeparator = busd.DOMAIN_SEPARATOR();
        // compute the domain separator manually using the underlying values
        bytes32 nameHash = keccak256(abi.encodePacked(busd.name()));
        bytes32 versionHash = keccak256(abi.encodePacked(busd.version()));
        bytes32 chainId = bytes32(block.chainid);
        bytes32 verifyingContract = bytes32(uint256(uint160(address(busd))));
        bytes32 computedDomainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                nameHash,
                versionHash,
                chainId,
                verifyingContract
            )
        );
        assertEq(computedDomainSeparator, domainSeparator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   INTERNAL HELPER FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _testTemps() internal returns (_TestTemps memory t) {
        (t.owner, t.privateKey) = _randomSigner();
        t.to = _randomNonZeroAddress();
        t.amount = _random();
        t.deadline = _random();
    }

    function _testEIP3009() internal returns (_TestEIP3009 memory t) {
        (t.from, t.privateKey) = _randomSigner();
        t.to = _randomNonZeroAddress();
        t.value = _random();
        // valid after is in the past
        t.validAfter = block.timestamp - 1;
        // valid before is in the future
        t.validBefore = block.timestamp + 1;
        t.nonce = bytes32(_random());
    }

    function _checkAllowanceAndNonce(_TestTemps memory t) internal {
        assertEq(busd.allowance(t.owner, t.to), t.amount);
        assertEq(busd.nonces(t.owner), t.nonce + 1);
    }

    function _signPermit(_TestTemps memory t) internal view {
        bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, t.owner, t.to, t.amount, t.nonce, t.deadline));
        bytes32 domainSeparator = busd.DOMAIN_SEPARATOR();
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);
    }

    function _signTransferWithAuthorization(_TestEIP3009 memory t) internal view {
        bytes32 innerHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH, t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce
            )
        );
        bytes32 domainSeparator = busd.DOMAIN_SEPARATOR();
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);
    }

    function _signReceiveWithAuthorization(_TestEIP3009 memory t) internal view {
        bytes32 innerHash = keccak256(
            abi.encode(
                RECEIVE_WITH_AUTHORIZATION_TYPEHASH, t.from, t.to, t.value, t.validAfter, t.validBefore, t.nonce
            )
        );
        bytes32 domainSeparator = busd.DOMAIN_SEPARATOR();
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);
    }

    function _signCancelAuthorization(_TestEIP3009 memory t) internal view {
        bytes32 innerHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, t.from, t.nonce));
        bytes32 domainSeparator = busd.DOMAIN_SEPARATOR();
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);
    }

    function _expectPermitEmitApproval(_TestTemps memory t) internal {
        vm.expectEmit(true, true, true, true);
        emit ERC20.Approval(t.owner, t.to, t.amount);
    }

    function _permit(_TestTemps memory t) internal {
        address token_ = address(busd);
        assembly ("memory-safe") {
            let m := mload(sub(t, 0x20))
            mstore(sub(t, 0x20), 0xd505accf)
            let success := call(gas(), token_, 0, sub(t, 0x04), 0xe4, 0x00, 0x00)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            mstore(sub(t, 0x20), m)
        }
    }

    function _mint(uint256 amount) internal {
        vm.prank(address(factory));
        busd.mint(address(this), amount);
    }
}
