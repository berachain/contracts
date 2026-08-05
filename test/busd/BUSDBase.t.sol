// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { StdCheats } from "forge-std/StdCheats.sol";
import { SoladyTest } from "solady/test/utils/SoladyTest.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { BUSD } from "src/busd/BUSD.sol";
import { CollateralVault } from "src/busd/CollateralVault.sol";
import { BUSDDeployer } from "src/busd/BUSDDeployer.sol";
import { BUSDFactoryReader } from "src/busd/BUSDFactoryReader.sol";
import { BUSDFactory, VaultAdmin } from "src/busd/BUSDFactory.sol";
import { MockDAI, MockUSDT, MockDummy } from "@mock/busd/MockAssets.sol";
import { MockPyth } from "@mock/oracle/MockPyth.sol";
import { MockOracle } from "@mock/oracle/MockOracle.sol";

abstract contract BUSDBaseTest is StdCheats, SoladyTest, Create2Deployer {
    // Roles
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    BUSDFactory internal factory;
    address internal governance = makeAddr("governance");
    address internal manager = makeAddr("manager");
    address internal pauser = makeAddr("pauser");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal polFeeCollector = makeAddr("polFeeCollector");
    address internal receiver = makeAddr("receiver");
    BUSD internal busd;
    CollateralVault daiVault;
    CollateralVault usdtVault;

    MockDAI dai = new MockDAI();
    uint256 daiBalance = 200e18;
    uint256 daiMintRate = 0.99e18;
    uint256 daiRedeemRate = 0.98e18;

    MockUSDT usdt = new MockUSDT();
    uint256 usdtBalance = 100_000e6;
    uint256 usdtMintRate = 0.99e18;
    uint256 usdtRedeemRate = 0.98e18;

    MockPyth pyth = new MockPyth();
    PythPriceOracle oracle;
    bytes32 daiFeed = keccak256("DAI/USD");
    bytes32 usdtFeed = keccak256("USDT/USD");

    BUSDFactoryReader internal factoryReader;

    Salt internal _busdSalt = Salt({ implementation: 0, proxy: 0 });
    Salt internal _busdFactorySalt = Salt({ implementation: 0, proxy: 1 });
    Salt internal _busdFactoryReaderSalt = Salt({ implementation: 0, proxy: 0 });

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        address _pythPriceOracleImpl = deployWithCreate2(256, type(PythPriceOracle).creationCode);
        oracle = PythPriceOracle(deployProxyWithCreate2(address(_pythPriceOracleImpl), 0));

        oracle.initialize(governance);

        vm.startPrank(governance);
        oracle.setPythSource(address(pyth));
        oracle.grantRole(MANAGER_ROLE, address(this));
        vm.stopPrank();

        pyth.setData(daiFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        oracle.setPriceFeed(address(dai), daiFeed);
        pyth.setData(usdtFeed, int64(99_993_210), uint64(31_155), int32(-8), block.timestamp);
        oracle.setPriceFeed(address(usdt), usdtFeed);
        BUSDDeployer deployer = new BUSDDeployer(
            governance,
            polFeeCollector,
            feeReceiver,
            _busdSalt,
            _busdFactorySalt,
            _busdFactoryReaderSalt,
            address(oracle)
        );
        busd = deployer.busd();
        factory = deployer.busdFactory();
        factoryReader = deployer.busdFactoryReader();

        dai.mint(address(this), daiBalance);
        usdt.mint(address(this), usdtBalance);

        vm.startPrank(governance);
        factory.grantRole(factory.MANAGER_ROLE(), manager);
        daiVault = CollateralVault(address(factory.createVault(address(dai))));
        usdtVault = CollateralVault(address(factory.createVault(address(usdt))));
        vm.stopPrank();

        vm.startPrank(manager);
        factory.setMintRate(address(dai), daiMintRate);
        factory.setRedeemRate(address(dai), daiRedeemRate);
        factory.setMintRate(address(usdt), usdtMintRate);
        factory.setRedeemRate(address(usdt), usdtRedeemRate);
        factory.grantRole(factory.PAUSER_ROLE(), pauser);
        vm.stopPrank();
    }
}
