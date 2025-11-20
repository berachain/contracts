// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { Salt } from "src/base/Salt.sol";

import "./POL.t.sol";

contract POLDeployerTest is Create2Deployer, POLTest {
    bytes32 private constant BLOCK_REWARD_CONTROLLER_INIT_CODE_HASH =
        keccak256(type(BlockRewardController).creationCode);
    bytes32 private constant BERA_CHEF_INIT_CODE_HASH = keccak256(type(BeraChef).creationCode);
    bytes32 private constant DISTRIBUTOR_INIT_CODE_HASH = keccak256(type(Distributor).creationCode);

    constructor() {
        BERA_CHEF_SALT = Salt({ implementation: 0, proxy: 1 });
        BLOCK_REWARD_CONTROLLER_SALT = Salt({ implementation: 0, proxy: 1 });
        DISTRIBUTOR_SALT = Salt({ implementation: 0, proxy: 1 });
        REWARDS_FACTORY_SALT = Salt({ implementation: 0, proxy: 1 });
    }

    // Empty setup to avoid the running setup of POLTest.
    // POLTest setup deploys the POL contracts.
    // Inside POL Deployer, salt for implementation contracts are is hardcoded as 0
    // If we don't override the setup, the test will fail as again it will try to deploy implementation contracts with
    // 0 salt and will cause create2 collision.
    function setUp() public override { }

    function test_DeployPOL() public {
        deployBGT(governance);
        console2.log("POLDeployer init code size", type(POLDeployer).creationCode.length);
        polDeployer = new POLDeployer(
            address(bgt),
            governance,
            BERA_CHEF_SALT,
            BLOCK_REWARD_CONTROLLER_SALT,
            DISTRIBUTOR_SALT,
            REWARDS_FACTORY_SALT,
            REWARD_VAULT_SALT
        );
        // verify the address of BeraChef
        verifyCreate2Address("BeraChef", BERA_CHEF_INIT_CODE_HASH, BERA_CHEF_SALT, address(polDeployer.beraChef()));
        // verify the address of BlockRewardController
        verifyCreate2Address(
            "BlockRewardController",
            BLOCK_REWARD_CONTROLLER_INIT_CODE_HASH,
            BLOCK_REWARD_CONTROLLER_SALT,
            address(polDeployer.blockRewardController())
        );
        // verify the address of Distributor
        verifyCreate2Address(
            "Distributor", DISTRIBUTOR_INIT_CODE_HASH, DISTRIBUTOR_SALT, address(polDeployer.distributor())
        );
    }

    function verifyCreate2Address(
        string memory name,
        bytes32 initCodeHash,
        Salt memory salt,
        address expected
    )
        internal
        pure
    {
        address impl = getCreate2Address(salt.implementation, initCodeHash);
        console2.log(string.concat(name, " implementation address"), impl);
        initCodeHash = keccak256(initCodeERC1967(impl));
        console2.log(string.concat(name, " init code hash"));
        console2.logBytes32(initCodeHash);
        address addr = getCreate2Address(salt.proxy, initCodeHash);
        console2.log(string.concat(name, " address"), addr);
        assertEq(addr, expected);
    }
}
