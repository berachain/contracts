// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBlockRewardController } from "../interfaces/IBlockRewardController.sol";
import { IBeaconDeposit } from "../interfaces/IBeaconDeposit.sol";
import { BGT } from "../BGT.sol";

/// @title BlockRewardController
/// @author Berachain Team
/// @notice The BlockRewardController contract is responsible for managing the reward rate of BGT.
/// @dev It should be owned by the governance module.
/// @dev It should also be the only contract that can mint the BGT token.
/// @dev The invariant(s) that should hold true are:
///      - processRewards() is only called at most once per block timestamp.
contract BlockRewardController is IBlockRewardController, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @notice The maximum value for base rate.
    uint256 public constant MAX_BASE_RATE = 5 * FixedPointMathLib.WAD;

    /// @notice The maximum value for reward rate.
    uint256 public constant MAX_REWARD_RATE = 5 * FixedPointMathLib.WAD;

    /// @notice The maximum value for the minimum reward rate after boosts accounting.
    uint256 public constant MAX_MIN_BOOSTED_REWARD_RATE = 10 * FixedPointMathLib.WAD;

    /// @notice The maximum value for boost multiplier.
    uint256 public constant MAX_BOOST_MULTIPLIER = 5 * FixedPointMathLib.WAD;

    /// @notice The maximum value for reward convexity parameter.
    uint256 public constant MAX_REWARD_CONVEXITY = FixedPointMathLib.WAD;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The BGT token contract that we are minting to the distributor.
    BGT public bgt;

    /// @notice The Beacon deposit contract to check the pubkey -> operator relationship.
    IBeaconDeposit public beaconDepositContract;

    /// @notice The distributor contract that receives the minted BGT.
    address public distributor;

    /// @notice The constant base rate for BGT.
    uint256 public baseRate;

    /// @notice The reward rate for BGT.
    uint256 public rewardRate;

    /// @notice The minimum reward rate for BGT after accounting for validator boosts.
    uint256 public minBoostedRewardRate;

    /// @notice The boost multiplier param in the function, determines the inflation cap, 18 dec.
    uint256 public boostMultiplier;

    /// @notice The reward convexity param in the function, determines how fast it converges to its max, 18 dec.
    int256 public rewardConvexity;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bgt,
        address _distributor,
        address _beaconDepositContract,
        address _governance
    )
        external
        initializer
    {
        __Ownable_init(_governance);
        __UUPSUpgradeable_init();
        bgt = BGT(_bgt);
        emit SetDistributor(_distributor);
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MODIFIER                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) {
            NotDistributor.selector.revertWith();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBlockRewardController
    function setBaseRate(uint256 _baseRate) external onlyOwner {
        if (_baseRate > MAX_BASE_RATE) {
            InvalidBaseRate.selector.revertWith();
        }
        emit BaseRateChanged(baseRate, _baseRate);
        baseRate = _baseRate;
    }

    /// @inheritdoc IBlockRewardController
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        if (_rewardRate > MAX_REWARD_RATE) {
            InvalidRewardRate.selector.revertWith();
        }
        emit RewardRateChanged(rewardRate, _rewardRate);
        rewardRate = _rewardRate;
    }

    /// @inheritdoc IBlockRewardController
    function setMinBoostedRewardRate(uint256 _minBoostedRewardRate) external onlyOwner {
        if (_minBoostedRewardRate > MAX_MIN_BOOSTED_REWARD_RATE) {
            InvalidMinBoostedRewardRate.selector.revertWith();
        }
        emit MinBoostedRewardRateChanged(minBoostedRewardRate, _minBoostedRewardRate);
        minBoostedRewardRate = _minBoostedRewardRate;
    }

    /// @inheritdoc IBlockRewardController
    function setBoostMultiplier(uint256 _boostMultiplier) external onlyOwner {
        if (_boostMultiplier > MAX_BOOST_MULTIPLIER) {
            InvalidBoostMultiplier.selector.revertWith();
        }
        emit BoostMultiplierChanged(boostMultiplier, _boostMultiplier);
        boostMultiplier = _boostMultiplier;
    }

    /// @inheritdoc IBlockRewardController
    function setRewardConvexity(uint256 _rewardConvexity) external onlyOwner {
        if (_rewardConvexity == 0 || _rewardConvexity > MAX_REWARD_CONVEXITY) {
            InvalidRewardConvexity.selector.revertWith();
        }
        emit RewardConvexityChanged(uint256(rewardConvexity), _rewardConvexity);
        // store as int256 to avoid casting during computation
        rewardConvexity = int256(_rewardConvexity);
    }

    /// @inheritdoc IBlockRewardController
    function setDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        emit SetDistributor(_distributor);
        distributor = _distributor;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*              DISTRIBUTOR FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBlockRewardController
    function computeReward(
        uint256 boostPower,
        uint256 _rewardRate,
        uint256 _boostMultiplier,
        int256 _rewardConvexity
    )
        public
        pure
        returns (uint256 reward)
    {
        // On conv == 0, mathematical result should be max reward even for boost == 0 (0^0 = 1)
        // but since BlockRewardController enforces conv > 0, we're not adding code for conv == 0 case
        if (boostPower > 0) {
            // Compute intermediate parameters for the reward formula
            uint256 one = FixedPointMathLib.WAD;

            if (boostPower == one) {
                // avoid approx errors in the following code
                reward = FixedPointMathLib.mulWad(_rewardRate, _boostMultiplier);
            } else {
                // boost^conv ∈ (0, 1]
                uint256 tmp_0 = uint256(FixedPointMathLib.powWad(int256(boostPower), _rewardConvexity));
                // 1 + mul * boost^conv ∈ [1, 1 + mul]
                uint256 tmp_1 = one + FixedPointMathLib.mulWad(_boostMultiplier, tmp_0);
                // 1 - 1 / (1 + mul * boost^conv) ∈ [0, mul / (1 + mul)]
                uint256 tmp_2 = one - FixedPointMathLib.divWad(one, tmp_1);

                // @dev Due to splitting fixed point ops, [mul / (1 + mul)] * (1 + mul) may be slightly > mul
                uint256 coeff = FixedPointMathLib.mulWad(tmp_2, one + _boostMultiplier);
                if (coeff > _boostMultiplier) coeff = _boostMultiplier;

                reward = FixedPointMathLib.mulWad(_rewardRate, coeff);
            }
        }
    }

    /// @inheritdoc IBlockRewardController
    function getMaxBGTPerBlock() public view returns (uint256 amount) {
        amount = computeReward(FixedPointMathLib.WAD, rewardRate, boostMultiplier, rewardConvexity);
        if (amount < minBoostedRewardRate) {
            amount = minBoostedRewardRate;
        }
        amount += baseRate;
    }

    /// @inheritdoc IBlockRewardController
    function processRewards(
        bytes calldata pubkey,
        uint64 nextTimestamp,
        bool isReady
    )
        external
        onlyDistributor
        returns (uint256)
    {
        uint256 base = baseRate;
        uint256 reward = 0;

        // Only compute vaults reward if berachef is ready
        if (isReady) {
            // Calculate the boost power for the validator
            uint256 boostPower = bgt.normalizedBoost(pubkey);
            reward = computeReward(boostPower, rewardRate, boostMultiplier, rewardConvexity);
            if (reward < minBoostedRewardRate) reward = minBoostedRewardRate;
        }

        emit BlockRewardProcessed(pubkey, nextTimestamp, base, reward);

        // Use the beaconDepositContract to fetch the operator, Its gauranteed to return a valid address.
        // Beacon Deposit contract will enforce validators to set an operator.
        address operator = beaconDepositContract.getOperator(pubkey);
        if (base > 0) bgt.mint(operator, base);

        // Mint the scaled rewards BGT for validator reward allocation to the distributor.
        if (reward > 0) bgt.mint(distributor, reward);

        return reward;
    }
}
