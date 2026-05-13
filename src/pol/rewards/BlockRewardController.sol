// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBlockRewardController } from "../interfaces/IBlockRewardController.sol";
import { IBeaconDeposit } from "../interfaces/IBeaconDeposit.sol";
import { BGT } from "../BGT.sol";
import { IWBERA } from "../interfaces/IWBERA.sol";

/// @title BlockRewardController
/// @author Berachain Team
/// @notice The BlockRewardController contract is responsible for managing the reward rate
/// and distributing WBERA (migrated from BGT).
/// @dev It should be owned by the governance module.
/// @dev The invariant(s) that should hold true are:
///      - processRewards() is only called at most once per block timestamp.
contract BlockRewardController is IBlockRewardController, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @notice The version of the contract.
    uint64 public constant VERSION = 2;

    /// @notice The constant base rate for the emission token sent to the validator's operator each block.
    uint256 internal constant _BASE_RATE = 0.4e18;

    /// @notice The constant reward rate for the emission token sent to the distributor each block.
    uint256 internal constant _REWARD_RATE = 1.305e18;

    /// @notice The WBERA token address.
    address public constant WBERA_ADDRESS = 0x6969696969696969696969696969696969696969;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The BGT token contract used internally for minting and redeeming to native tokens.
    BGT public bgt;

    /// @notice The Beacon deposit contract to check the pubkey -> operator relationship.
    IBeaconDeposit public beaconDepositContract;

    /// @notice The distributor contract that receives the minted WBERA.
    address public distributor;

    /// @dev Deprecated. Replaced by the `BASE_RATE` constant. Slot retained to preserve storage layout.
    uint256 internal _baseRate;

    /// @dev Deprecated. Replaced by the `REWARD_RATE` constant. Slot retained to preserve storage layout.
    uint256 internal _rewardRate;

    /// @dev Deprecated
    /// @notice The minimum reward rate for BGT after accounting for validator boosts.
    uint256 internal _minBoostedRewardRate;

    /// @dev Deprecated
    /// @notice The boost multiplier param in the function, determines the inflation cap, 18 dec.
    uint256 internal _boostMultiplier;

    /// @dev Deprecated
    /// @notice The reward convexity param in the function, determines how fast it converges to its max, 18 dec.
    int256 internal _rewardConvexity;

    /// @notice The WBERA token contract used to wrap and distribute rewards.
    IWBERA public wbera;

    receive() external payable { }

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

    /// @notice V2 initializer: migrates the emission token from BGT to WBERA.
    /// @dev Sets the WBERA contract used for wrapping native tokens before distribution,
    /// and clears deprecated rate and boost parameters from V1 (rates are now constants).
    function initialize() external reinitializer(VERSION) onlyOwner {
        wbera = IWBERA(WBERA_ADDRESS);

        emit BaseRateChanged(_baseRate, _BASE_RATE);
        emit RewardRateChanged(_rewardRate, _REWARD_RATE);

        _baseRate = 0;
        _rewardRate = 0;
        _minBoostedRewardRate = 0;
        _boostMultiplier = 0;
        _rewardConvexity = 0;
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
    function baseRate() external pure returns (uint256) {
        return _BASE_RATE;
    }

    /// @inheritdoc IBlockRewardController
    function rewardRate() external pure returns (uint256) {
        return _REWARD_RATE;
    }

    /// @inheritdoc IBlockRewardController
    function getMaxBGTPerBlock() public pure returns (uint256 amount) {
        return _BASE_RATE + _REWARD_RATE;
    }

    /// @inheritdoc IBlockRewardController
    function getMaxEmissionPerBlock() public pure returns (uint256 amount) {
        return _BASE_RATE + _REWARD_RATE;
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
        uint256 reward = isReady ? _REWARD_RATE : 0;
        emit BlockRewardProcessed(pubkey, nextTimestamp, _BASE_RATE, reward);

        address operator = beaconDepositContract.getOperator(pubkey);
        if (_BASE_RATE != 0) _handleMinting(operator, _BASE_RATE);
        if (reward != 0) _handleMinting(distributor, reward);

        return reward;
    }

    /// @inheritdoc IBlockRewardController
    function burnExceedingBalance() external onlyDistributor {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            SafeTransferLib.safeTransferETH(address(0), balance);
            emit ExceedingBalanceBurnt(balance);
        }
    }

    /// @dev Handler to ensure distributeFor will not halt: as long as the consensus layer has not started minting
    /// native tokens directly to this contract, this function guarantees by minting and redeeming BGT as needed that
    /// there is always enough
    /// native balance available to wrap and deliver emissions as WBERA. This wrapper remains necessary until native
    /// token minting support arrives at the consensus layer.
    function _handleMinting(address receiver, uint256 amount) internal {
        if (address(this).balance < amount) {
            bgt.mint(address(this), amount);
            bgt.redeem(address(this), amount);
        }

        wbera.deposit{ value: amount }();
        wbera.transfer(receiver, amount);
    }
}
