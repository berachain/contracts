// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBGT } from "src/pol/interfaces/IBGT.sol";
import { IBlockRewardController, IPOLErrors } from "src/pol/interfaces/IBlockRewardController.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { WBERA } from "src/WBERA.sol";

import { BeaconDepositMock, POLTest, Vm } from "./POL.t.sol";

contract BlockRewardControllerTest is POLTest {
    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view {
        assertEq(blockRewardController.owner(), governance);
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public {
        vm.expectRevert();
        blockRewardController.transferOwnership(address(1));

        vm.expectRevert();
        blockRewardController.setDistributor(address(1));

        address newImpl = address(new BlockRewardController());
        vm.expectRevert();
        blockRewardController.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public {
        address newImpl = address(new BlockRewardController());
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(newImpl);
        vm.prank(governance);
        blockRewardController.upgradeToAndCall(newImpl, bytes(""));
        assertEq(
            vm.load(address(blockRewardController), ERC1967Utils.IMPLEMENTATION_SLOT),
            bytes32(uint256(uint160(newImpl)))
        );
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public {
        vm.expectRevert();
        blockRewardController.initialize(address(bgt), address(distributor), address(beraChef), address(governance));
    }

    /// @dev V2 reinitializer should fail if called again
    function test_InitializeV2_FailIfCalledAgain() public {
        vm.prank(governance);
        vm.expectRevert();
        blockRewardController.initialize();
    }

    /// @dev V2 reinitializer wires WBERA and zeroes deprecated fields; rates are now constants.
    function test_InitializeV2() public {
        BlockRewardController freshController = new BlockRewardController();
        BlockRewardController freshProxy =
            BlockRewardController(payable(deployProxyWithCreate2(address(freshController), 99)));

        freshProxy.initialize(address(bgt), address(distributor), beaconDepositContract, governance);
        vm.prank(governance);
        freshProxy.initialize();

        assertEq(address(freshProxy.wbera()), address(wbera));
        assertEq(freshProxy.baseRate(), 0.4e18);
        assertEq(freshProxy.rewardRate(), 1.305e18);
        assertEq(freshProxy.VERSION(), 2);
    }

    function test_SetDistributor_FailIfZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        blockRewardController.setDistributor(address(0));
    }

    /// @dev Ensure that the distributor is set
    function test_SetDistributor() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        address _distributor = address(distributor);
        emit IBlockRewardController.SetDistributor(_distributor);
        blockRewardController.setDistributor(_distributor);
        assertEq(blockRewardController.distributor(), _distributor);
    }

    /// @dev Should fail if not the distributor
    function test_FailIfNotDistributor() public {
        vm.expectRevert();
        blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);
    }

    /// @dev Should process rewards via native balance, sending emission token to operator and distributor
    function test_ProcessRewards() public {
        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        uint256 rewardRate = blockRewardController.rewardRate();
        vm.deal(address(blockRewardController), baseRate + rewardRate);

        uint256 operatorEmissionTokenBefore = emissionToken.balanceOf(operator);
        uint256 distributorEmissionTokenBefore = emissionToken.balanceOf(address(distributor));

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(
            valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, baseRate, rewardRate
        );

        assertEq(blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true), rewardRate);

        assertEq(emissionToken.balanceOf(operator) - operatorEmissionTokenBefore, baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)) - distributorEmissionTokenBefore, rewardRate);
    }

    /// @dev Should process rewards via BGT mint/redeem when no native balance
    function test_ProcessRewards_ViaMintRedeem() public {
        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        uint256 rewardRate = blockRewardController.rewardRate();

        // No native balance on the controller; fund BGT so mint/redeem can produce native tokens.
        vm.deal(address(bgt), address(bgt).balance + baseRate + rewardRate);

        uint256 operatorEmissionTokenBefore = emissionToken.balanceOf(operator);
        uint256 distributorEmissionTokenBefore = emissionToken.balanceOf(address(distributor));

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(
            valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, baseRate, rewardRate
        );

        assertEq(blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true), rewardRate);

        assertEq(emissionToken.balanceOf(operator) - operatorEmissionTokenBefore, baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)) - distributorEmissionTokenBefore, rewardRate);
    }

    /// @dev Fuzz over native balance to exercise both the direct-wrap and the BGT mint/redeem
    /// fallback paths in _handleMinting.
    function testFuzz_ProcessRewards(uint256 nativeBalance, uint256 boostVal0, uint256 boostVal1) public {
        bytes memory valPubkey1 = "validator 1 pubkey";
        address operator1 = makeAddr("operator");
        BeaconDepositMock(beaconDepositContract).setOperator(valPubkey1, operator1);

        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        uint256 rewardRate = blockRewardController.rewardRate();
        uint256 totalNeeded = baseRate + rewardRate;
        nativeBalance = _bound(nativeBalance, 0, totalNeeded);

        vm.deal(address(blockRewardController), nativeBalance);
        // Fund BGT contract to cover mint/redeem for any shortfall.
        uint256 mintShortfall = totalNeeded - nativeBalance;
        if (mintShortfall > 0) {
            vm.deal(address(bgt), address(bgt).balance + mintShortfall);
        }

        _helper_Boost(address(0x2), boostVal0, valData.pubkey);
        _helper_Boost(address(0x3), boostVal1, valPubkey1);

        uint256 bgtSupplyBefore = bgt.totalSupply();
        uint256 operatorEmissionTokenBefore = emissionToken.balanceOf(operator);
        uint256 distributorEmissionTokenBefore = emissionToken.balanceOf(address(distributor));

        vm.prank(address(distributor));
        uint256 reward = blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);

        assertEq(reward, rewardRate);
        assertEq(emissionToken.balanceOf(operator) - operatorEmissionTokenBefore, baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)) - distributorEmissionTokenBefore, rewardRate);

        // BGT supply should remain unchanged: any minted BGT is immediately redeemed.
        assertEq(bgt.totalSupply(), bgtSupplyBefore, "BGT supply should be unchanged after mint/redeem cycle");
    }

    /// @dev When the controller has enough native balance, _handleMinting should NOT call bgt.mint/redeem
    function test_ProcessRewards_SkipsMintRedeemWhenBalanceSufficient() public {
        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        uint256 rewardRate = blockRewardController.rewardRate();
        vm.deal(address(blockRewardController), baseRate + rewardRate);
        uint256 bgtSupplyBefore = bgt.totalSupply();

        vm.prank(address(distributor));
        blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);

        assertEq(bgt.totalSupply(), bgtSupplyBefore, "BGT supply should not change when balance is sufficient");
        assertEq(emissionToken.balanceOf(operator), baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)), rewardRate);
    }

    /// @dev When the controller has insufficient native balance, _handleMinting should mint BGT and redeem for native
    function test_ProcessRewards_MintRedeemWhenBalanceInsufficient() public {
        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        uint256 rewardRate = blockRewardController.rewardRate();
        vm.deal(address(bgt), address(bgt).balance + baseRate + rewardRate);

        vm.prank(address(distributor));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(blockRewardController), baseRate)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.redeem, (address(blockRewardController), baseRate)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(blockRewardController), rewardRate)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.redeem, (address(blockRewardController), rewardRate)));
        blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);

        assertEq(emissionToken.balanceOf(operator), baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)), rewardRate);
    }

    /// @dev When the controller has partial balance, only the shortfall should trigger mint/redeem
    function test_ProcessRewards_PartialBalance() public {
        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        uint256 rewardRate = blockRewardController.rewardRate();
        vm.deal(address(blockRewardController), baseRate);
        vm.deal(address(bgt), address(bgt).balance + rewardRate);

        vm.prank(address(distributor));
        blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);

        assertEq(emissionToken.balanceOf(operator), baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)), rewardRate);
    }

    /// @dev When isReady=false, only baseRate goes to operator, nothing to distributor
    function test_ProcessRewards_OnlyBaseRateWhenNotReady() public {
        test_SetDistributor();

        uint256 baseRate = blockRewardController.baseRate();
        vm.deal(address(blockRewardController), baseRate);

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, baseRate, 0);
        uint256 reward = blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, false);

        assertEq(reward, 0);
        assertEq(emissionToken.balanceOf(operator), baseRate);
        assertEq(emissionToken.balanceOf(address(distributor)), 0);
    }

    /// @dev Controller's native balance should decrease by the total minted amount
    function test_ProcessRewards_NativeBalanceDecreasesAfterMinting() public {
        test_SetDistributor();

        uint256 totalRate = blockRewardController.baseRate() + blockRewardController.rewardRate();
        vm.deal(address(blockRewardController), 10 ether);
        uint256 balanceBefore = address(blockRewardController).balance;

        vm.prank(address(distributor));
        blockRewardController.processRewards(valData.pubkey, DISTRIBUTE_FOR_TIMESTAMP, true);

        assertEq(balanceBefore - address(blockRewardController).balance, totalRate);
    }

    /// @dev getMaxBGTPerBlock returns BASE_RATE + REWARD_RATE
    function test_GetMaxBGTPerBlock() public view {
        assertEq(
            blockRewardController.getMaxBGTPerBlock(),
            blockRewardController.baseRate() + blockRewardController.rewardRate()
        );
    }

    function test_BurnExceedingBalance_OnlyDistributor() public {
        vm.expectRevert(IPOLErrors.NotDistributor.selector);
        blockRewardController.burnExceedingBalance();
    }

    function test_BurnExceedingBalance() public {
        test_SetDistributor();
        vm.deal(address(blockRewardController), 3 ether);

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.ExceedingBalanceBurnt(3 ether);
        blockRewardController.burnExceedingBalance();

        assertEq(address(blockRewardController).balance, 0);
    }

    function test_BurnExceedingBalance_ZeroBalance() public {
        test_SetDistributor();

        vm.recordLogs();
        vm.prank(address(distributor));
        blockRewardController.burnExceedingBalance();

        // No ExceedingBalanceBurnt event should have been emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    function _helper_Mint(address user, uint256 amount) internal {
        vm.deal(address(bgt), address(bgt).balance + amount);
        vm.prank(address(blockRewardController));
        bgt.mint(user, amount);
    }

    function _helper_QueueBoost(address user, bytes memory pubkey, uint256 amount) internal {
        _helper_Mint(user, amount);
        vm.prank(user);
        bgt.queueBoost(pubkey, uint128(amount));
    }

    function _helper_ActivateBoost(address caller, address user, bytes memory pubkey, uint256 amount) internal {
        _helper_QueueBoost(user, pubkey, amount);
        (uint32 blockNumberLast,) = bgt.boostedQueue(user, valData.pubkey);
        vm.roll(block.number + blockNumberLast + HISTORY_BUFFER_LENGTH + 1);
        vm.prank(caller);
        bgt.activateBoost(user, pubkey);
    }

    function _helper_Boost(address user, uint256 amount, bytes memory pubkey) internal {
        amount = _bound(amount, 1, type(uint128).max / 2);
        _helper_ActivateBoost(user, user, pubkey, amount);
    }
}
