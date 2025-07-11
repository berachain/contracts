// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1967 } from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { POLTest } from "./POL.t.sol";
import { MockERC20 } from "@mock/token/MockERC20.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";
import { IBGTIncentiveDistributor } from "src/pol/interfaces/IBGTIncentiveDistributor.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";

contract BGTIncentiveReceiverTest is POLTest {
    MockERC20 internal token;

    address claimUser = 0xEE8d5FD148c18e79927d8DE79d8E688Abf0b3af5;
    uint256 claimAmount = 62_452_330_923_580_633_174;
    bytes32 internal merkleRoot = hex"9541b35c714a035b8ede23f1cd3daf0c9e7d3e9075ddc3438a42dea643afcafd";
    bytes32 internal merkleRootUpdated = hex"0000000000000000000000000000000000000000000000000000000000000000";
    bytes32[] internal validProof = [
        bytes32(hex"deb76e27dbbe2905221af8a914d322a71129586ea7a6d1bbefbdd607b40c4278"),
        bytes32(hex"5a07bc5a623395d4ee91da3625b71c03dacc8110dbf9ede5fed0395b2807316a"),
        bytes32(hex"df5bd8dad45aa9c779728cb50b42dfcd8e9b76b1ff551b220f54bece18c5846e")
    ];

    bytes32[] internal invalidProof = [bytes32(hex"0000000000000000000000000000000000000000000000000000000000000000")];

    function setUp() public override(POLTest) {
        super.setUp();
        token = new MockERC20();
    }

    function test_ReceiveIncentive(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        token.mint(address(this), amount);
        token.approve(address(bgtIncentiveDistributor), amount);

        BGTIncentiveDistributor(bgtIncentiveDistributor).receiveIncentive(valData.pubkey, address(token), amount);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(bgtIncentiveDistributor)), amount);
        assertEq(
            BGTIncentiveDistributor(bgtIncentiveDistributor).incentiveTokensPerValidator(
                valData.pubkey, address(token)
            ),
            amount
        );
    }

    function test_ReceiveIncentive_RevertCatch(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        token.mint(address(this), amount);

        // test transferFrom without allowance, should revert
        assertEq(token.allowance(address(this), address(bgtIncentiveDistributor)), 0);
        vm.expectRevert();
        BGTIncentiveDistributor(bgtIncentiveDistributor).receiveIncentive(valData.pubkey, address(token), amount);

        // test transferFrom without allowance, revet should be catched and return false
        assertEq(token.allowance(address(this), address(bgtIncentiveDistributor)), 0);
        bytes memory data =
            abi.encodeCall(IBGTIncentiveDistributor.receiveIncentive, (valData.pubkey, address(token), amount));
        (bool success,) = bgtIncentiveDistributor.call(data);
        assertEq(success, false);

        // test transferFrom with allowance, should not revert
        token.approve(address(bgtIncentiveDistributor), amount);
        assertEq(token.allowance(address(this), address(bgtIncentiveDistributor)), amount);
        data = abi.encodeCall(IBGTIncentiveDistributor.receiveIncentive, (valData.pubkey, address(token), amount));
        (success,) = bgtIncentiveDistributor.call(data);
        assertEq(success, true);
        assertEq(token.allowance(address(this), address(bgtIncentiveDistributor)), 0);
    }

    function test_updateRewardsMetadata() public returns (bytes32 identifier) {
        identifier = keccak256(abi.encodePacked(valData.pubkey, address(token)));

        IBGTIncentiveDistributor.Distribution memory distribution = IBGTIncentiveDistributor.Distribution({
            identifier: identifier,
            pubkey: valData.pubkey,
            token: address(token),
            merkleRoot: merkleRoot,
            proof: bytes32(0)
        });

        IBGTIncentiveDistributor.Distribution[] memory distributions = new IBGTIncentiveDistributor.Distribution[](1);
        distributions[0] = distribution;

        vm.startPrank(bgtIncentiveReceiverManager);
        BGTIncentiveDistributor(bgtIncentiveDistributor).updateRewardsMetadata(distributions);
        (address _token, bytes32 _merkleRoot, bytes32 _proof, uint256 _activeAt, bytes memory _pubkey) =
            BGTIncentiveDistributor(bgtIncentiveDistributor).rewards(identifier);
        assertEq(_token, address(token));
        assertEq(_merkleRoot, merkleRoot);
        assertEq(_proof, bytes32(0));
        assertEq(_pubkey, valData.pubkey);
        assertEq(_activeAt, block.timestamp + BGTIncentiveDistributor(bgtIncentiveDistributor).rewardClaimDelay());
    }

    function test_updateRewardsMetadata_UpdateRoot() public {
        bytes32 identifier = test_updateRewardsMetadata();

        IBGTIncentiveDistributor.Distribution memory distribution = IBGTIncentiveDistributor.Distribution({
            identifier: identifier,
            pubkey: valData.pubkey,
            token: address(token),
            merkleRoot: merkleRootUpdated,
            proof: bytes32(0)
        });

        IBGTIncentiveDistributor.Distribution[] memory distributions = new IBGTIncentiveDistributor.Distribution[](1);
        distributions[0] = distribution;

        vm.startPrank(bgtIncentiveReceiverManager);
        BGTIncentiveDistributor(bgtIncentiveDistributor).updateRewardsMetadata(distributions);
        (address _token, bytes32 _merkleRoot, bytes32 _proof, uint256 _activeAt, bytes memory _pubkey) =
            BGTIncentiveDistributor(bgtIncentiveDistributor).rewards(identifier);
        assertEq(_token, address(token));
        assertEq(_merkleRoot, merkleRootUpdated);
        assertEq(_proof, bytes32(0));
        assertEq(_pubkey, valData.pubkey);
        assertEq(_activeAt, block.timestamp + BGTIncentiveDistributor(bgtIncentiveDistributor).rewardClaimDelay());
    }

    function test_UpdateRewardsMetadata_Revert_TokenMismatch() public {
        address newToken = makeAddr("newToken");

        bytes32 identifier = test_updateRewardsMetadata();

        IBGTIncentiveDistributor.Distribution memory distribution = IBGTIncentiveDistributor.Distribution({
            identifier: identifier,
            pubkey: valData.pubkey,
            token: newToken,
            merkleRoot: merkleRootUpdated,
            proof: bytes32(0)
        });

        IBGTIncentiveDistributor.Distribution[] memory distributions = new IBGTIncentiveDistributor.Distribution[](1);
        distributions[0] = distribution;

        vm.startPrank(bgtIncentiveReceiverManager);
        vm.expectRevert(IPOLErrors.InvalidToken.selector);
        BGTIncentiveDistributor(bgtIncentiveDistributor).updateRewardsMetadata(distributions);
    }

    function test_ClaimReward() public {
        _helperReceiveIncentive(claimAmount);
        bytes32 identifier = test_updateRewardsMetadata();

        vm.warp(vm.getBlockTimestamp() + BGTIncentiveDistributor(bgtIncentiveDistributor).rewardClaimDelay() + 1);

        // preconditions
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(bgtIncentiveDistributor)), claimAmount);

        IBGTIncentiveDistributor.Claim memory claim = IBGTIncentiveDistributor.Claim({
            identifier: identifier,
            account: claimUser,
            amount: claimAmount,
            merkleProof: validProof
        });

        IBGTIncentiveDistributor.Claim[] memory claims = new IBGTIncentiveDistributor.Claim[](1);
        claims[0] = claim;

        BGTIncentiveDistributor(bgtIncentiveDistributor).claim(claims);
        assertEq(token.balanceOf(claimUser), claimAmount);
        assertEq(token.balanceOf(address(bgtIncentiveDistributor)), 0);
        assertEq(BGTIncentiveDistributor(bgtIncentiveDistributor).claimed(identifier, claimUser), claimAmount);
    }

    function test_ClaimReward_Revert_NotClaimable() public {
        _helperReceiveIncentive(claimAmount);
        bytes32 identifier = test_updateRewardsMetadata();

        vm.warp(vm.getBlockTimestamp() + BGTIncentiveDistributor(bgtIncentiveDistributor).rewardClaimDelay() - 1);

        // preconditions
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(bgtIncentiveDistributor)), claimAmount);

        IBGTIncentiveDistributor.Claim memory claim = IBGTIncentiveDistributor.Claim({
            identifier: identifier,
            account: claimUser,
            amount: claimAmount,
            merkleProof: validProof
        });

        IBGTIncentiveDistributor.Claim[] memory claims = new IBGTIncentiveDistributor.Claim[](1);
        claims[0] = claim;

        vm.expectRevert(IPOLErrors.RewardInactive.selector);
        BGTIncentiveDistributor(bgtIncentiveDistributor).claim(claims);
    }

    function test_ClaimReward_Revert_InvalidProof() public {
        _helperReceiveIncentive(claimAmount);
        bytes32 identifier = test_updateRewardsMetadata();

        vm.warp(vm.getBlockTimestamp() + BGTIncentiveDistributor(bgtIncentiveDistributor).rewardClaimDelay() + 1);

        // preconditions
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(bgtIncentiveDistributor)), claimAmount);

        IBGTIncentiveDistributor.Claim memory claim = IBGTIncentiveDistributor.Claim({
            identifier: identifier,
            account: claimUser,
            amount: claimAmount,
            merkleProof: invalidProof
        });

        IBGTIncentiveDistributor.Claim[] memory claims = new IBGTIncentiveDistributor.Claim[](1);
        claims[0] = claim;

        vm.expectRevert(IPOLErrors.InvalidProof.selector);
        BGTIncentiveDistributor(bgtIncentiveDistributor).claim(claims);
    }

    function _helperReceiveIncentive(uint256 amount) internal {
        token.mint(address(this), amount);
        token.approve(address(bgtIncentiveDistributor), amount);
        BGTIncentiveDistributor(bgtIncentiveDistributor).receiveIncentive(valData.pubkey, address(token), amount);
    }
}
