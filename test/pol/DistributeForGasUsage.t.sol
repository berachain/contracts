// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { IBGT } from "src/pol/interfaces/IBGT.sol";
import { IBlockRewardController } from "src/pol/interfaces/IBlockRewardController.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { BeaconRootsHelperTest } from "./BeaconRootsHelper.t.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";

contract DistributeForGasUsageTest is BeaconRootsHelperTest {
    address internal manager = makeAddr("manager");
    bytes32 internal defaultAdminRole;
    bytes32 internal managerRole;

    uint256 internal constant NUMBER_OF_WEIGHTS = 10;
    uint256 internal constant NUMBER_OF_INCENTIVE_TOKENS = 2;
    uint256 internal constant MIN_INCENTIVE_RATE = 1e18;
    uint256 internal constant INCENTIVE_RATE = 1e18;

    address[] internal incentiveTokens;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        initDefaultRewardAllocation = false;
        super.setUp();

        defaultAdminRole = distributor.DEFAULT_ADMIN_ROLE();
        managerRole = distributor.MANAGER_ROLE();

        vm.prank(governance);
        distributor.grantRole(managerRole, manager);
    }

    /// @dev Distribute using the default reward allocation if none is set.
    function test_Distribute(uint256 randomNumber) public {
        randomNumber;
        _helper_SetDefaultRewardAllocationWithIncentiveTokens(NUMBER_OF_WEIGHTS);

        IBeraChef.RewardAllocation memory ra = beraChef.getDefaultRewardAllocation();
        assertEq(ra.weights.length, NUMBER_OF_WEIGHTS);
        assertEq(incentiveTokens.length, NUMBER_OF_WEIGHTS * NUMBER_OF_INCENTIVE_TOKENS);

        // expect a call to mint the BGT to the distributor
        bytes memory data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 1);

        distributor.distributeFor(
            DISTRIBUTE_FOR_TIMESTAMP, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );
    }

    /// @dev Test the `multicall` function for distributeFor.
    function test_DistributeMulticall() public {
        _helper_SetDefaultRewardAllocationWithIncentiveTokens(NUMBER_OF_WEIGHTS);
        // expect 3 calls to process the rewards
        bytes memory data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true));
        vm.expectCall(address(blockRewardController), data, 1);
        data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP + 1, true));
        vm.expectCall(address(blockRewardController), data, 1);
        data =
            abi.encodeCall(IBlockRewardController.processRewards, (valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP + 2, true));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect 3 calls to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), TEST_BGT_PER_BLOCK));
        vm.expectCall(address(bgt), data, 3);

        // call distributeFor 3 times in a single multicall
        bytes[] memory callData = new bytes[](3);

        // Function selector for distributeFor(uint64,uint64,bytes,bytes32[],bytes32[])
        bytes4 selector = bytes4(keccak256("distributeFor(uint64,uint64,bytes,bytes32[],bytes32[])"));

        callData[0] = abi.encodeWithSelector(
            selector,
            DISTRIBUTE_FOR_TIMESTAMP,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
        callData[1] = abi.encodeWithSelector(
            selector,
            DISTRIBUTE_FOR_TIMESTAMP + 1,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
        callData[2] = abi.encodeWithSelector(
            selector,
            DISTRIBUTE_FOR_TIMESTAMP + 2,
            valData.index,
            valData.pubkey,
            valData.proposerIndexProof,
            valData.pubkeyProof
        );
        distributor.multicall(callData);
    }

    function _helper_CreateStakingToken() internal returns (address) {
        MockERC20 stakingToken = new MockERC20();
        stakingToken.initialize("Staking Token", "STK");
        return address(stakingToken);
    }

    function _helper_CreateRewardVault() internal returns (address) {
        RewardVault vault = RewardVault(factory.createRewardVault(_helper_CreateStakingToken()));
        vm.prank(governance);
        vault.setMaxIncentiveTokensCount(uint8(NUMBER_OF_INCENTIVE_TOKENS));
        return address(vault);
    }

    function _helper_SetDefaultRewardAllocationWithIncentiveTokens(uint256 numberOfWeights) internal {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](numberOfWeights);
        uint96 totalWeight = 10_000;
        uint96 weight = totalWeight / uint96(numberOfWeights);

        for (uint256 i = 0; i < numberOfWeights; i++) {
            address vault = _helper_CreateRewardVault();
            if (weight > totalWeight) {
                weight = totalWeight;
            }
            weights[i] = IBeraChef.Weight(vault, weight);
            vm.prank(governance);
            beraChef.setVaultWhitelistedStatus(vault, true, "");
            _helper_WhitelistIncentiveTokens(vault);
            totalWeight -= weight;
        }
        vm.prank(governance);
        beraChef.setDefaultRewardAllocation(IBeraChef.RewardAllocation(1, weights));
    }

    function _helper_WhitelistIncentiveTokens(address vault) public {
        uint256 count = RewardVault(vault).maxIncentiveTokensCount();

        for (uint256 i = 0; i < count; i++) {
            MockERC20 incentiveToken = new MockERC20();
            incentiveToken.initialize("Incentive Token", "ITK");

            // Whitelist the token
            vm.prank(governance);
            RewardVault(vault).whitelistIncentiveToken(address(incentiveToken), MIN_INCENTIVE_RATE, address(this));

            _helper_AddIncentives(vault, address(incentiveToken), 100 * 1e18);
            incentiveTokens.push(address(incentiveToken));
        }
    }

    function _helper_AddIncentives(address vault, address token, uint256 amount) internal {
        MockERC20(token).mint(address(this), type(uint256).max);
        MockERC20(token).approve(vault, type(uint256).max);

        RewardVault(vault).addIncentive(token, amount, INCENTIVE_RATE);
    }
}
