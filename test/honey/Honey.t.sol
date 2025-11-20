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

import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyDeployer } from "src/honey/HoneyDeployer.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { MockHoney, FaultyMockHoney } from "@mock/honey/MockHoney.sol";
import { MockOracle } from "@mock/oracle/MockOracle.sol";
import { Salt } from "src/base/Salt.sol";

contract HoneyTest is StdCheats, SoladyTest {
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

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address internal governance = makeAddr("governance");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal polFeeCollector = makeAddr("polFeeCollector");
    // address used to test transfer and transferFrom
    address internal spender = makeAddr("spender");
    Honey internal honey;
    HoneyDeployer internal deployer;
    HoneyFactory internal factory;

    Salt internal _honeySalt = Salt({ implementation: 0, proxy: 0 });
    Salt internal _honeyFactorySalt = Salt({ implementation: 0, proxy: 1 });
    Salt internal _honeyFactoryReaderSalt = Salt({ implementation: 0, proxy: 1 });

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        MockOracle oracle = new MockOracle();
        deployer = new HoneyDeployer(
            governance,
            feeReceiver,
            polFeeCollector,
            _honeySalt,
            _honeyFactorySalt,
            _honeyFactoryReaderSalt,
            address(oracle)
        );
        honey = deployer.honey();
        factory = deployer.honeyFactory();
        assertEq(honey.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance), true);
    }

    function test_Initialize_FailsIfZeroAddresses() public {
        Honey newHoney = Honey(LibClone.deployERC1967(address(new Honey())));

        // initialize with zero address governance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newHoney.initialize(address(0), address(factory));

        // initialize with zero address factory
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.ZeroAddress.selector));
        newHoney.initialize(governance, address(0));
    }

    function test_MetaData() public {
        assertEq(honey.name(), "Honey");
        assertEq(honey.symbol(), "HONEY");
        assertEq(honey.decimals(), 18);
    }

    /// @dev Test that minting Honey fails if the caller is not the factory.
    function test_Mint_FailIfNotFactory() public {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        honey.mint(address(this), 100);
    }

    /// @dev Test that minting Honey fails if the total supply overflows.
    function testFuzz_Mint_TotalSupplyOverflow(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0);
        amount1 = _bound(amount1, type(uint256).max - amount0 + 1, type(uint256).max);

        vm.startPrank(address(factory));
        honey.mint(address(this), amount0);

        vm.expectRevert(ERC20.TotalSupplyOverflow.selector);
        honey.mint(address(this), amount1);
    }

    /// @dev Test minting Honey
    function test_Mint() public {
        testFuzz_Mint(100e18);
    }

    /// @dev Test minting Honey
    function testFuzz_Mint(uint256 mintAmount) public {
        uint256 totalSupplyPre = honey.totalSupply();
        uint256 balancePre = honey.balanceOf(address(this));

        vm.expectEmit();
        emit ERC20.Transfer(address(0), address(this), mintAmount);
        _mint(mintAmount);

        uint256 totalSupplyPost = honey.totalSupply();
        uint256 balancePost = honey.balanceOf(address(this));
        assertEq(totalSupplyPost, totalSupplyPre + mintAmount);
        assertEq(balancePost, balancePre + mintAmount);
    }

    /// @dev Test that burning Honey fails if the caller is not the factory.
    function test_Burn_FailIfNotFactory() public {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        honey.burn(address(this), 100);
    }

    /// @dev Test that burning Honey fails if there is insufficient balance.
    function test_Burn_FailIfInsufficientBalance() public {
        testFuzz_Burn_FailIfInsufficientBalance(0, 50);
    }

    /// @dev Test that burning Honey fails if there is insufficient balance.
    function testFuzz_Burn_FailIfInsufficientBalance(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(burnAmount > 0);
        mintAmount = _bound(mintAmount, 0, burnAmount - 1);
        _mint(mintAmount);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        vm.prank(address(factory));
        honey.burn(address(this), burnAmount);
    }

    /// @dev Test burning Honey
    function test_Burn() public {
        testFuzz_Burn(100, 50);
    }

    /// @dev Test burning Honey
    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0);
        burnAmount = _bound(burnAmount, 0, mintAmount);
        _mint(mintAmount);

        vm.expectEmit();
        emit ERC20.Transfer(address(this), address(0), burnAmount);
        vm.prank(address(factory));
        honey.burn(address(this), burnAmount);

        assertEq(honey.balanceOf(address(this)), mintAmount - burnAmount);
        assertEq(honey.totalSupply(), mintAmount - burnAmount);
    }

    function test_Approve() public {
        testFuzz_Approve(spender, 1e18);
    }

    function testFuzz_Approve(address _spender, uint256 amount) public {
        vm.expectEmit();
        emit ERC20.Approval(address(this), _spender, amount);
        bool approveSuccess = honey.approve(_spender, amount);
        uint256 allowance = honey.allowance(address(this), _spender);

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
        honey.transfer(to, amount);
    }

    function test_Transfer() public {
        testFuzz_Transfer(governance, 1e18);
    }

    function testFuzz_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(this));
        _mint(amount);

        vm.expectEmit();
        emit ERC20.Transfer(address(this), to, amount);
        bool transferSuccess = honey.transfer(to, amount);

        assertTrue(transferSuccess);
        assertEq(honey.totalSupply(), amount);
        assertEq(honey.balanceOf(address(this)), 0);
        assertEq(honey.balanceOf(to), amount);
    }

    function test_TransferFrom_FailsIfInsufficientAllowance() public {
        testFuzz_TransferFrom_FailsIfInsufficientAllowance(governance, 1e18);
    }

    function testFuzz_TransferFrom_FailsIfInsufficientAllowance(address to, uint256 amount) public {
        vm.assume(amount > 0);
        _mint(amount);
        // address(this) approves randomCaller to spend (amount - 1) Honey.
        honey.approve(spender, amount - 1);

        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        honey.transferFrom(address(this), to, amount);
    }

    function test_TransferFrom_FailsIfInsufficientBalance() public {
        testFuzz_TransferFrom_FailsIfInsufficientBalance(governance, 1e18);
    }

    function testFuzz_TransferFrom_FailsIfInsufficientBalance(address to, uint256 amount) public {
        vm.assume(amount > 0);
        _mint(amount - 1);
        // address(this) approves spender to spend amount Honey.
        honey.approve(spender, amount);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        honey.transferFrom(address(this), to, amount);
    }

    function test_TransferFrom() public {
        testFuzz_TransferFrom(governance, 1e18);
    }

    function testFuzz_TransferFrom(address to, uint256 amount) public {
        vm.assume(to != address(this));
        _mint(amount);
        // address(this) approves randomCaller to spend amount Honey.
        honey.approve(spender, amount);
        vm.expectEmit();
        emit ERC20.Transfer(address(this), to, amount);
        vm.prank(spender);
        bool transferSuccess = honey.transferFrom(address(this), to, amount);

        assertTrue(transferSuccess);
        assertEq(honey.totalSupply(), amount);
        assertEq(honey.balanceOf(address(this)), 0);
        assertEq(honey.balanceOf(to), amount);
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
        address newHoneyImpl = address(new Honey());
        vm.assume(caller != governance);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN_ROLE
            )
        );
        honey.upgradeToAndCall(newHoneyImpl, bytes(""));
    }

    function test_UpgradeToFaultyHoney() public {
        assertEq(honey.name(), "Honey");
        assertEq(honey.symbol(), "HONEY");

        address honeyFactory = honey.factory();

        address faultyHoneyOwner = address(0x3);
        vm.startPrank(faultyHoneyOwner);
        FaultyMockHoney faultyHoneyImpl = new FaultyMockHoney();
        vm.stopPrank();

        vm.expectEmit();
        emit IERC1967.Upgraded(address(faultyHoneyImpl));
        // Only governance can upgrade the contract, since it's the owner of the Proxy
        vm.prank(governance);
        honey.upgradeToAndCall(address(faultyHoneyImpl), bytes(""));

        // Initialize the faultyHoney through the proxy
        FaultyMockHoney(address(honey)).initialize(faultyHoneyOwner);

        // Factory slot has not initializated on the Proxy storage
        // So factory is equal to address(0)
        // "collidedFactoryValue" variable instead, has taken the value of the factory address
        // since it's pointing to the "original" factory slot of the storage
        assertNotEq(honey.factory(), honeyFactory);
        assertEq(FaultyMockHoney(address(honey)).collidedFactoryValue(), honeyFactory);
        assertEq(honey.factory(), address(0x0));
    }

    function test_UpgradeTo() public {
        // mint 1 honey
        _mint(1e18);

        assertEq(honey.name(), "Honey");
        assertEq(honey.symbol(), "HONEY");

        // get the totalSupply and the factory address from current implementation
        uint256 honeyMintedBeforeUpgrade = honey.totalSupply();
        address honeyFactory = honey.factory();

        MockHoney mockHoneyImpl = new MockHoney();

        vm.expectEmit();
        emit IERC1967.Upgraded(address(mockHoneyImpl));
        // Only governance can upgrade the contract
        vm.prank(governance);
        honey.upgradeToAndCall(address(mockHoneyImpl), bytes(""));
        MockHoney(address(honey)).initialize(governance);

        assertEq(honey.name(), "MockHoney");
        assertEq(honey.symbol(), "MOCK_HONEY");
        // Check factory address and total supply
        assertEq(honey.factory(), honeyFactory);
        assertEq(honey.totalSupply(), honeyMintedBeforeUpgrade);
    }

    function test_UpgradeToMockHoneyGovernanceCannotUpgradeWhenOwnerOfProxyChanges() public {
        MockHoney mockHoneyImpl = new MockHoney();

        address mockHoneyOwner = address(0x3);
        vm.expectEmit();
        emit IERC1967.Upgraded(address(mockHoneyImpl));
        // Only governance can upgrade the contract
        vm.prank(governance);
        honey.upgradeToAndCall(address(mockHoneyImpl), bytes(""));
        MockHoney(address(honey)).initialize(mockHoneyOwner);

        // Check governance cannot upgrade the contract because it's not the owner of the Proxy
        address newImplementation = address(new MockHoney());
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        vm.startPrank(governance);
        honey.upgradeToAndCall(newImplementation, bytes(""));
    }

    function test_Pause() public {
        address blackhat = makeAddr("blackhat");
        vm.prank(address(factory));
        honey.mint(blackhat, 100e18);
        assertEq(false, honey.paused());

        vm.prank(governance);
        honey.setPaused(true);
        assertEq(true, honey.paused());

        address blackhatSink = makeAddr("blackhatSink");
        vm.prank(blackhat);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        honey.transfer(blackhatSink, 100e18);

        vm.prank(governance);
        honey.setPaused(false);
        assertEq(false, honey.paused());

        vm.prank(blackhat);
        honey.transfer(blackhatSink, 100e18);
        assertEq(100e18, honey.balanceOf(blackhatSink));
    }

    function test_Blacklist() public {
        address blackhat = makeAddr("blackhat");
        vm.prank(address(factory));
        honey.mint(blackhat, 100e18);
        assertEq(false, honey.isBlacklistedWallet(blackhat));

        vm.prank(governance);
        honey.setBlacklisted(blackhat, true);
        assertEq(true, honey.isBlacklistedWallet(blackhat));

        address blackhatSink = makeAddr("blackhatSink");
        vm.prank(blackhat);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.BlacklistedWallet.selector));
        honey.transfer(blackhatSink, 100e18);

        vm.prank(governance);
        honey.setBlacklisted(blackhat, false);
        assertEq(false, honey.isBlacklistedWallet(blackhat));

        vm.prank(blackhat);
        honey.transfer(blackhatSink, 100e18);
        assertEq(100e18, honey.balanceOf(blackhatSink));
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

    function _checkAllowanceAndNonce(_TestTemps memory t) internal {
        assertEq(honey.allowance(t.owner, t.to), t.amount);
        assertEq(honey.nonces(t.owner), t.nonce + 1);
    }

    function _signPermit(_TestTemps memory t) internal view {
        bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, t.owner, t.to, t.amount, t.nonce, t.deadline));
        bytes32 domainSeparator = honey.DOMAIN_SEPARATOR();
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);
    }

    function _expectPermitEmitApproval(_TestTemps memory t) internal {
        vm.expectEmit(true, true, true, true);
        emit ERC20.Approval(t.owner, t.to, t.amount);
    }

    function _permit(_TestTemps memory t) internal {
        address token_ = address(honey);
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
        honey.mint(address(this), amount);
    }
}
