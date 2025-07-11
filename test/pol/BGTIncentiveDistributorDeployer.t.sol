// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { BGTIncentiveDistributorDeployer } from "src/pol/BGTIncentiveDistributorDeployer.sol";

import "./POL.t.sol";

contract BGTIncentiveDistributorTest is Create2Deployer, Test {
    bytes32 private constant BGT_INCENTIVE_DISTRIBUTOR_INIT_CODE_HASH =
        keccak256(type(BGTIncentiveDistributor).creationCode);
    uint256 internal constant BGT_INCENTIVE_DISTRIBUTOR_SALT = 1;

    function setUp() public { }

    function test_DeployBGTIncentiveDistributor() public {
        address defaultOwner = makeAddr("defaultOwner");

        console2.log("BGTIncentiveDistributor init code size", type(BGTIncentiveDistributor).creationCode.length);

        BGTIncentiveDistributorDeployer bgtIncentiveDistributorDeployer =
            new BGTIncentiveDistributorDeployer(defaultOwner, BGT_INCENTIVE_DISTRIBUTOR_SALT);
        // verify the address of BGTIncentiveDistributor
        verifyCreate2Address(
            "BGTIncentiveDistributor",
            BGT_INCENTIVE_DISTRIBUTOR_INIT_CODE_HASH,
            BGT_INCENTIVE_DISTRIBUTOR_SALT,
            address(bgtIncentiveDistributorDeployer.bgtIncentiveDistributor())
        );
    }

    function verifyCreate2Address(
        string memory name,
        bytes32 initCodeHash,
        uint256 salt,
        address expected
    )
        internal
        pure
    {
        // The implementation salt for the BGTIncentiveDistributor is set to 1 in the deployer contract.
        address impl = getCreate2Address(1, initCodeHash);
        console2.log(string.concat(name, " implementation address"), impl);
        initCodeHash = keccak256(initCodeERC1967(impl));
        console2.log(string.concat(name, " init code hash"));
        console2.logBytes32(initCodeHash);
        address addr = getCreate2Address(salt, initCodeHash);
        console2.log(string.concat(name, " address"), addr);
        assertEq(addr, expected);
    }
}
