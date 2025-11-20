// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import { DeployHelper } from "src/base/DeployHelper.sol";
import { Salt } from "src/base/Salt.sol";
import { MockERC20 } from "../mock/token/MockERC20.sol";
import { MockERC20WithConstructor } from "../mock/token/MockERC20WithConstructor.sol";
import { MockDummy } from "../mock/honey/MockAssets.sol";

contract DeployHelperTest is DeployHelper, Test {
    bytes private constant CONTRACT_INIT_CODE = type(MockDummy).creationCode;
    bytes private constant CONTRACT_ARGS_INIT_CODE = type(MockERC20WithConstructor).creationCode;
    bytes private constant PROXY_CONTRACT_INIT_CODE = type(MockERC20).creationCode;
    string private constant PEPPER_1 = "LoremIpsumDolorSitAmet";
    string private constant PEPPER_2 = "ConsecteturAdipiscingElit";

    constructor() {
        _setPepper(PEPPER_1);
    }

    function test_deploy() public {
        address predictedAddr = _predictAddress(CONTRACT_INIT_CODE);
        address deployedAddr = _deploy(CONTRACT_INIT_CODE);
        assertEq(predictedAddr, deployedAddr);

        // A different cryptographic pepper must result in a different deploy
        _setPepper(PEPPER_2);
        predictedAddr = _predictAddress(CONTRACT_INIT_CODE);
        assertNotEq(predictedAddr, deployedAddr);

        // A different chain ID must result in a different deploy
        _setPepper(PEPPER_1);
        vm.chainId(10_000);
        predictedAddr = _predictAddress(CONTRACT_INIT_CODE);
        assertNotEq(predictedAddr, deployedAddr);
    }

    function test_deployWithArgs() public {
        string memory name = "Token";
        string memory symbol = "TKN";
        uint256 initialSupply = 100e18;
        bytes memory args = abi.encode(name, symbol, initialSupply);

        address predictedAddr = _predictAddressWithArgs(CONTRACT_ARGS_INIT_CODE, args);
        address deployedAddr = _deployWithArgs(CONTRACT_ARGS_INIT_CODE, args);
        assertEq(predictedAddr, deployedAddr);

        // A different cryptographic pepper must result in a different deploy
        _setPepper(PEPPER_2);
        predictedAddr = _predictAddressWithArgs(CONTRACT_ARGS_INIT_CODE, args);
        assertNotEq(predictedAddr, deployedAddr);

        // A different chain ID must result in a different deploy
        _setPepper(PEPPER_1);
        vm.chainId(10_000);
        predictedAddr = _predictAddressWithArgs(CONTRACT_ARGS_INIT_CODE, args);
        assertNotEq(predictedAddr, deployedAddr);
    }

    function test_deployProxy() public {
        address predictedAddr = _predictProxyAddress(PROXY_CONTRACT_INIT_CODE);

        Salt memory salt = _saltsForProxy(PROXY_CONTRACT_INIT_CODE);
        address impl = deployWithCreate2(salt.implementation, PROXY_CONTRACT_INIT_CODE);
        address deployedAddr = deployProxyWithCreate2(impl, salt.proxy);
        assertEq(predictedAddr, deployedAddr);

        // A different cryptographic pepper must result in a different deploy
        _setPepper(PEPPER_2);
        predictedAddr = _predictProxyAddress(PROXY_CONTRACT_INIT_CODE);
        assertNotEq(predictedAddr, deployedAddr);

        // A different chain ID must result in a different deploy
        _setPepper(PEPPER_1);
        vm.chainId(10_000);
        predictedAddr = _predictProxyAddress(PROXY_CONTRACT_INIT_CODE);
        assertNotEq(predictedAddr, deployedAddr);
    }
}
