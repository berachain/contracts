// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { CollateralVault } from "src/busd/CollateralVault.sol";
import { BUSDBaseTest, BUSDFactory } from "./BUSDBase.t.sol";
import { IBUSDFactory } from "src/busd/IBUSDFactory.sol";
import { MockAsset } from "@mock/busd/MockAssets.sol";

contract BUSDFactoryReaderTest is BUSDBaseTest {
    function setUp() public override {
        super.setUp();
    }

    /// @notice This test ensures that preview functions are consistent in the way
    /// previewMintCollaterals -> previewMintBUSD and with the actual minting process.
    function testFuzz_PreviewRequiredCollateral(uint256 busdMint) public {
        busdMint = _bound(busdMint, 0, type(uint128).max);

        uint256[] memory requiredCollaterals = factoryReader.previewMintCollaterals(address(dai), busdMint);
        uint256 daiCollateral = requiredCollaterals[0];
        _ensureTokenBalance(dai, daiCollateral);

        (uint256[] memory collaterals,) = factoryReader.previewMintBUSD(address(dai), daiCollateral);
        assertEq(daiCollateral, collaterals[0]);

        uint256 mintedBUSDs = _factoryMint(dai, daiCollateral, false);
        assertEq(busdMint, mintedBUSDs);
    }

    /// @notice This test ensures that preview functions are consistent in the way
    /// previewMintBUSD -> previewMintCollaterals and with the actual minting process.
    function testFuzz_PreviewMint(uint256 daiMint) public {
        // Since previewMintBUSD(1) = 0.99 = 0, the same amount having 0 or 1 as last digit would always give same
        // result in previewMintBUSD(amount). The wayback function will always return the 0-terminated amount.
        // So let's ensure the last digit is not 1.

        daiMint = _bound(daiMint, 0, type(uint128).max);
        if (daiMint % 10 == 1) {
            daiMint -= 1;
        }

        _ensureTokenBalance(dai, daiMint);

        (uint256[] memory collaterals, uint256 busdPreview) = factoryReader.previewMintBUSD(address(dai), daiMint);
        assertEq(daiMint, collaterals[0]);

        collaterals = factoryReader.previewMintCollaterals(address(dai), busdPreview);
        assertEq(daiMint, collaterals[0]);

        uint256 mintedBUSDs = _factoryMint(dai, daiMint, false);
        assertEq(busdPreview, mintedBUSDs);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _ensureTokenBalance(ERC20 asset, uint256 amount) internal {
        uint256 balance = asset.balanceOf((address(this)));
        if (balance < amount) {
            uint256 missing = amount - balance;
            MockAsset(address(asset)).mint(address(this), missing);
        }
    }

    function _factoryMint(ERC20 asset, uint256 amount, bool expectBasketMode) internal returns (uint256 mintedBUSDs) {
        asset.approve(address(factory), amount);
        mintedBUSDs = factory.mint(address(asset), amount, address(this), expectBasketMode);
    }
}
