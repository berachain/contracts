// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPyth } from "@pythnetwork/IPyth.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { IHoneyErrors } from "./IHoneyErrors.sol";
import { IHoneyFactory } from "./IHoneyFactory.sol";
import { IHoneyFactoryPythWrapper } from "./IHoneyFactoryPythWrapper.sol";
import { IHoneyFactoryReader } from "./IHoneyFactoryReader.sol";
import { Utils } from "../libraries/Utils.sol";
import { VaultAdmin } from "./VaultAdmin.sol";

/// @notice Wrapper around HoneyFactory, for minting and redeeming Honey while updating Pyth oracle.
/// @author Berachain Team
contract HoneyFactoryPythWrapper is IHoneyFactoryPythWrapper, IHoneyErrors {
    using Utils for bytes4;

    address public honey;
    address public factory;
    address public pyth;
    address public factoryReader;

    constructor(address factory_, address pythPriceOracle_, address factoryReader_) {
        if (factory_ == address(0)) ZeroAddress.selector.revertWith();
        if (pythPriceOracle_ == address(0)) ZeroAddress.selector.revertWith();
        if (factoryReader_ == address(0)) ZeroAddress.selector.revertWith();
        honey = address(IHoneyFactory(factory_).honey());
        if (honey == address(0)) ZeroAddress.selector.revertWith();

        factory = factory_;
        factoryReader = factoryReader_;
        pyth = pythPriceOracle_;
    }

    /// @inheritdoc IHoneyFactoryPythWrapper
    function mint(
        bytes[] calldata updateData,
        address asset,
        uint256 amount,
        address receiver,
        bool expectBasketMode
    )
        external
        payable
        returns (uint256 minted)
    {
        _updatePyth(updateData);

        VaultAdmin v = VaultAdmin(factory);
        IHoneyFactoryReader reader = IHoneyFactoryReader(factoryReader);

        (uint256[] memory collaterals,) = reader.previewMintHoney(asset, amount);
        uint256 numCollaterals = v.numRegisteredAssets();
        for (uint256 i = 0; i < numCollaterals; i++) {
            _getForFactory(v.registeredAssets(i), collaterals[i]);
        }

        minted = IHoneyFactory(factory).mint(asset, amount, receiver, expectBasketMode);

        // Transfer back any leftover
        for (uint256 i = 0; i < numCollaterals; i++) {
            asset = v.registeredAssets(i);
            _refundAnyLeftover(asset);
        }
    }

    /// @inheritdoc IHoneyFactoryPythWrapper
    function redeem(
        bytes[] calldata updateData,
        address asset,
        uint256 honeyAmount,
        address receiver,
        bool expectBasketMode
    )
        external
        payable
        returns (uint256[] memory amounts)
    {
        _updatePyth(updateData);
        _getForFactory(honey, honeyAmount);

        amounts = IHoneyFactory(factory).redeem(asset, honeyAmount, receiver, expectBasketMode);
        // Transfer back any leftover honey that might arise from basket mode redeem logic.
        _refundAnyLeftover(honey);
    }

    /// @inheritdoc IHoneyFactoryPythWrapper
    function liquidate(
        bytes[] calldata updateData,
        address badCollateral,
        address goodCollateral,
        uint256 goodAmount
    )
        external
        payable
        returns (uint256 badAmount)
    {
        _updatePyth(updateData);
        _getForFactory(goodCollateral, goodAmount);

        badAmount = IHoneyFactory(factory).liquidate(badCollateral, goodCollateral, goodAmount);

        // Transfer back bad collateral
        SafeTransferLib.safeTransfer(badCollateral, msg.sender, badAmount);

        // Transfer back any leftover of good collateral
        _refundAnyLeftover(goodCollateral);
    }

    /// @inheritdoc IHoneyFactoryPythWrapper
    function recapitalize(bytes[] calldata updateData, address asset, uint256 amount) external payable {
        _updatePyth(updateData);
        _getForFactory(asset, amount);

        IHoneyFactory(factory).recapitalize(asset, amount);

        _refundAnyLeftover(asset);
    }

    ///////// INTERNAL /////////

    function _updatePyth(bytes[] memory updateData) internal {
        uint256 balance = address(this).balance;
        uint256 fee = IPyth(pyth).getUpdateFee(updateData);
        if (balance < fee) InsufficientBalanceToPayPythFee.selector.revertWith();
        IPyth(pyth).updatePriceFeeds{ value: fee }(updateData);

        // Refund any leftover:
        if (fee < balance) {
            SafeTransferLib.safeTransferETH(msg.sender, balance - fee);
        }

        emit PythOracleUpdated(fee);
    }

    function _getForFactory(address asset, uint256 amount) internal {
        if (amount == 0) {
            return;
        }
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);
        SafeTransferLib.safeApprove(asset, factory, amount);
    }

    function _refundAnyLeftover(address asset) internal {
        uint256 amount = ERC20(asset).balanceOf(address(this));
        if (amount > 0) {
            SafeTransferLib.safeTransfer(asset, msg.sender, amount);
        }
    }
}
