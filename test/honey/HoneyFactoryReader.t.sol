// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyBaseTest, HoneyFactory } from "./HoneyBase.t.sol";
import { IHoneyFactory } from "src/honey/IHoneyFactory.sol";
import { MockAsset } from "@mock/honey/MockAssets.sol";

contract HoneyFactoryReaderTest is HoneyBaseTest {
    function setUp() public override {
        super.setUp();
    }

    /// @notice This test ensures that preview functions are consistent in the way
    /// previewMintCollaterals -> previewMintHoney and with the actual minting process.
    function testFuzz_PreviewRequiredCollateral(uint256 honeyMint) public {
        honeyMint = _bound(honeyMint, 0, type(uint128).max);

        uint256[] memory requiredCollaterals = factoryReader.previewMintCollaterals(address(dai), honeyMint);
        uint256 daiCollateral = requiredCollaterals[0];
        _ensureTokenBalance(dai, daiCollateral);

        (uint256[] memory collaterals,) = factoryReader.previewMintHoney(address(dai), daiCollateral);
        assertEq(daiCollateral, collaterals[0]);

        uint256 mintedHoneys = _factoryMint(dai, daiCollateral, false);
        assertEq(honeyMint, mintedHoneys);
    }

    /// @notice This test ensures that preview functions are consistent in the way
    /// previewMintHoney -> previewMintCollaterals and with the actual minting process.
    function testFuzz_PreviewMint(uint256 daiMint) public {
        // Since previewMintHoney(1) = 0.99 = 0, the same amount having 0 or 1 as last digit would always give same
        // result in previewMintHoney(amount). The wayback function will always return the 0-terminated amount.
        // So let's ensure the last digit is not 1.

        daiMint = _bound(daiMint, 0, type(uint128).max);
        if (daiMint % 10 == 1) {
            daiMint -= 1;
        }

        _ensureTokenBalance(dai, daiMint);

        (uint256[] memory collaterals, uint256 honeyPreview) = factoryReader.previewMintHoney(address(dai), daiMint);
        assertEq(daiMint, collaterals[0]);

        collaterals = factoryReader.previewMintCollaterals(address(dai), honeyPreview);
        assertEq(daiMint, collaterals[0]);

        uint256 mintedHoneys = _factoryMint(dai, daiMint, false);
        assertEq(honeyPreview, mintedHoneys);
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

    function _factoryMint(ERC20 asset, uint256 amount, bool expectBasketMode) internal returns (uint256 mintedHoneys) {
        asset.approve(address(factory), amount);
        mintedHoneys = factory.mint(address(asset), amount, address(this), expectBasketMode);
    }
}
