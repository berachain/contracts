// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IPyth } from "@pythnetwork/IPyth.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { IBUSDErrors } from "./IBUSDErrors.sol";
import { IBUSDFactory } from "./IBUSDFactory.sol";
import { IBUSDFactoryPythWrapper } from "./IBUSDFactoryPythWrapper.sol";
import { IBUSDFactoryReader } from "./IBUSDFactoryReader.sol";
import { Utils } from "../libraries/Utils.sol";
import { VaultAdmin } from "./VaultAdmin.sol";

/// @notice Wrapper around BUSDFactory, for minting and redeeming BUSD while updating Pyth oracle.
/// @author Berachain Team
contract BUSDFactoryPythWrapper is IBUSDFactoryPythWrapper, IBUSDErrors {
    using Utils for bytes4;

    address public busd;
    address public factory;
    address public pyth;
    address public factoryReader;

    constructor(address factory_, address pythPriceOracle_, address factoryReader_) {
        if (factory_ == address(0)) ZeroAddress.selector.revertWith();
        if (pythPriceOracle_ == address(0)) ZeroAddress.selector.revertWith();
        if (factoryReader_ == address(0)) ZeroAddress.selector.revertWith();
        busd = address(IBUSDFactory(factory_).busd());
        if (busd == address(0)) ZeroAddress.selector.revertWith();

        factory = factory_;
        factoryReader = factoryReader_;
        pyth = pythPriceOracle_;
    }

    /// @inheritdoc IBUSDFactoryPythWrapper
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
        IBUSDFactoryReader reader = IBUSDFactoryReader(factoryReader);

        (uint256[] memory collaterals,) = reader.previewMintBUSD(asset, amount);
        uint256 numCollaterals = v.numRegisteredAssets();
        for (uint256 i = 0; i < numCollaterals; i++) {
            _getForFactory(v.registeredAssets(i), collaterals[i]);
        }

        minted = IBUSDFactory(factory).mint(asset, amount, receiver, expectBasketMode);

        // Transfer back any leftover
        for (uint256 i = 0; i < numCollaterals; i++) {
            asset = v.registeredAssets(i);
            _refundAnyLeftover(asset);
        }
    }

    /// @inheritdoc IBUSDFactoryPythWrapper
    function redeem(
        bytes[] calldata updateData,
        address asset,
        uint256 busdAmount,
        address receiver,
        bool expectBasketMode
    )
        external
        payable
        returns (uint256[] memory amounts)
    {
        _updatePyth(updateData);
        _getForFactory(busd, busdAmount);

        amounts = IBUSDFactory(factory).redeem(asset, busdAmount, receiver, expectBasketMode);
        // Transfer back any leftover BUSD that might arise from basket mode redeem logic.
        _refundAnyLeftover(busd);
    }

    /// @inheritdoc IBUSDFactoryPythWrapper
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

        badAmount = IBUSDFactory(factory).liquidate(badCollateral, goodCollateral, goodAmount);

        // Transfer back bad collateral
        SafeTransferLib.safeTransfer(badCollateral, msg.sender, badAmount);

        // Transfer back any leftover of good collateral
        _refundAnyLeftover(goodCollateral);
    }

    /// @inheritdoc IBUSDFactoryPythWrapper
    function recapitalize(bytes[] calldata updateData, address asset, uint256 amount) external payable {
        _updatePyth(updateData);
        _getForFactory(asset, amount);

        IBUSDFactory(factory).recapitalize(asset, amount);

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
