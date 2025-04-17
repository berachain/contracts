// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/// @notice Interface of Honey errors
interface IHoneyErrors {
    // Signature: 0xd92e233d
    error ZeroAddress();
    // Signature: 0x14799671
    error MismatchedOwner(address owner, address expectedOwner);
    // Signature: 0x38bfcc16
    error VaultAlreadyRegistered(address asset);
    // Signature: 0x1a2a9e87
    error AssetNotRegistered(address asset);
    // Signature: 0x536dd9ef
    error UnauthorizedCaller(address caller, address expectedCaller);
    // Signature: 0xada46d16
    error OverOneHundredPercentRate(uint256 rate);
    // Signature: 0x71fba9d0
    error UnderNinetyEightPercentRate(uint256 rate);
    // Signature: 0x32cc7236
    error NotFactory();
    // Signature: 0xb97fded1
    error InsufficientAssets(uint256 assets, uint256 shares);
    // Signature: 0x6ba2e418
    error AssetIsBadCollateral(address asset);
    // Signature: 0x2595dbe7
    error ExceedRelativeCap();
    // Signature: 0x6dabf61e
    error ExceedGlobalCap();
    // Signature: 0x07091331
    error LiquidationDisabled();
    // Signature: 0x867344a8
    error AssetIsNotBadCollateral(address asset);
    // Signature: 0x0dc86ad3
    error LiquidationWithReferenceCollateral();
    // Signature: 0xda9f8b34
    error VaultPaused();
    // Signature: 0x168cecf7
    error ZeroWeight(address asset);
    // Signature: 0x10e4809e
    error RecapitalizeNotNeeded(address asset);
    // Signature: 0x2dd78c7e
    error InsufficientRecapitalizeAmount(uint256 amount);
    // Signature: 0xc64200e9
    error AmountOutOfRange();
    // Signature: 0x2201a6c3
    error NotPegged(address asset);
    // Signature: 0x1f2a2005
    error ZeroAmount();
    // Signature: 0x6ce14a8b
    error UnexpectedBasketModeStatus();
    // Signature: 0x5419864a
    error CapCanCauseDenialOfService();
    // Signature: 0xcd09f603
    error InvalidCustodyInfoInput();
}
