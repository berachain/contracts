// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { MockERC20WithConstructor } from "../mock/token/MockERC20WithConstructor.sol";

contract MockDeployer is Create2Deployer {
    function deploy(uint256 salt, bytes memory initCode) external returns (address addr) {
        return deployWithCreate2(salt, initCode);
    }

    function deployWithArgs(uint256 salt, bytes memory initCode, bytes memory args) external returns (address addr) {
        return deployWithCreate2WithArgs(salt, initCode, args);
    }
}

contract Create2DeployerTest is Test, Create2Deployer {
    bytes32 private constant BERA_CHEF_INIT_CODE_HASH = keccak256(type(BeraChef).creationCode);
    MockDeployer internal deployer;

    function setUp() public {
        deployer = new MockDeployer();
    }

    function test_DeployWithCreate2() public {
        address addr = deployWithCreate2(0, type(BeraChef).creationCode);
        assertEq(addr, getCreate2Address(0, BERA_CHEF_INIT_CODE_HASH));
    }

    function test_DeployWithCreate2WithArgs() public {
        address addr = deployWithCreate2WithArgs(
            0, type(MockERC20WithConstructor).creationCode, abi.encode("MockERC20", "MCK", 1000)
        );
        assertEq(
            addr,
            getCreate2AddressWithArgs(
                0, type(MockERC20WithConstructor).creationCode, abi.encode("MockERC20", "MCK", 1000)
            )
        );
    }

    function test_DeployWithCreate2_FailIfAlreadyDeployed() public {
        deployer.deploy(0, type(BeraChef).creationCode);
        vm.expectRevert(Create2Deployer.DeploymentFailed.selector);
        deployer.deploy(0, type(BeraChef).creationCode);
    }

    function test_DeployWithCreate2WithArgs_FailIfAlreadyDeployed() public {
        deployer.deployWithArgs(0, type(MockERC20WithConstructor).creationCode, abi.encode("MockERC20", "MCK", 1000));
        vm.expectRevert(Create2Deployer.DeploymentFailed.selector);
        deployer.deployWithArgs(0, type(MockERC20WithConstructor).creationCode, abi.encode("MockERC20", "MCK", 1000));
    }

    function test_DeployProxyWithCreate2() public {
        address impl = deployWithCreate2(0, type(BeraChef).creationCode);
        address addr = deployProxyWithCreate2(impl, 0);
        assertEq(addr, getCreate2ProxyAddress(impl, 0));
    }

    function test_DeployProxyWithCreate2_FailIfAlreadyDeployed() public {
        address impl = deployWithCreate2(0, type(BeraChef).creationCode);
        // deploy the proxy
        deployProxyWithCreate2(impl, 2);
        // try to deploy the same proxy again, should revert.
        vm.expectRevert(Create2Deployer.DeploymentFailed.selector);
        deployer.deploy(2, initCodeERC1967(impl));
    }
}
