// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainType } from "../base/Chain.sol";

struct HoneyAddresses {
    address honey;
    address honeyImpl;
    address honeyFactory;
    address honeyFactoryReader;
    address honeyFactoryImpl;
    address honeyFactoryReaderImpl;
    address collateralVaultImpl;
    address honeyFactoryPythWrapper;
}

abstract contract HoneyAddressBook {
    HoneyAddresses internal _honeyAddresses;

    constructor(ChainType chainType) {
        if (chainType == ChainType.Mainnet) {
            _honeyAddresses = _getMainnetHoneyAddresses();
        } else if (chainType == ChainType.Testnet) {
            _honeyAddresses = _getTestnetHoneyAddresses();
        } else if (chainType == ChainType.Devnet) {
            _honeyAddresses = _getDevnetHoneyAddresses();
        } else {
            _honeyAddresses = _getAnvilHoneyAddresses();
        }
    }

    /// @notice Mainnet addresses
    /// @dev Some of this contracts were deployed with a different context, hence their adddress should not be updated
    /// even if the predicted ones are different.
    function _getMainnetHoneyAddresses() private pure returns (HoneyAddresses memory) {
        return HoneyAddresses({
            honey: 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce,
            honeyImpl: 0x3caE8dC9A2E2D2106CE1a0ffDBdF21AbcC870bF8,
            honeyFactory: 0xA4aFef880F5cE1f63c9fb48F661E27F8B4216401,
            honeyFactoryReader: 0x285e147060CDc5ba902786d3A471224ee6cE0F91,
            honeyFactoryImpl: 0xF51C5a7B48410c4c4f99d353622d365481BDE7e7,
            honeyFactoryReaderImpl: 0x91C54526A9f8D0391F64392f24C7E8ff94A5f4fB,
            collateralVaultImpl: 0xAa4f2Bc7a06c89BEAB5125D82e25D4166b4a4681,
            honeyFactoryPythWrapper: 0x4b7cb1c197f8EE4d309866B16C2c12E3B4E7E606
        });
    }

    /// @notice Bepolia addresses
    /// @dev Some of this contracts were deployed with a different context, hence their adddress should not be updated
    /// even if the predicted ones are different.
    function _getTestnetHoneyAddresses() private pure returns (HoneyAddresses memory) {
        return HoneyAddresses({
            honey: 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce,
            honeyImpl: 0x114Af1Ad4c6FeBCB9222B7D6AF6141E7a34775Fe,
            honeyFactory: 0xA4aFef880F5cE1f63c9fb48F661E27F8B4216401,
            honeyFactoryReader: 0x285e147060CDc5ba902786d3A471224ee6cE0F91,
            honeyFactoryImpl: 0x3Ba6452ED6C57f4E1A6334E0C3b810c481AdaC64,
            honeyFactoryReaderImpl: 0x22ee76216B1b7E4f34CF1417da3E4773F7cbA8E6,
            collateralVaultImpl: 0xE3689043e7F860FbC0c814839cd7dF5022223172,
            honeyFactoryPythWrapper: 0x4b7cb1c197f8EE4d309866B16C2c12E3B4E7E606
        });
    }

    /// @notice Devnet addresses
    function _getDevnetHoneyAddresses() private pure returns (HoneyAddresses memory) {
        return HoneyAddresses({
            honey: 0x60Cd2DB29edf02c6514821498Ceabc61A845BbC2,
            honeyImpl: 0xbd5e55e69c3Fd0c89d153DF60C8B1afb2D72E500,
            honeyFactory: 0x6DFf70A6327b343801997f7fE20d192849863c5e,
            honeyFactoryReader: 0xf1CF3467C9508dfa6D1197F5359419856B3A3300,
            honeyFactoryImpl: 0xec5e1a0B097BD27B1C244Ab5557a52160200dB3A,
            honeyFactoryReaderImpl: 0x52d5848Ab7A304369cd2879DAfd9Ed3349E8ebB1,
            collateralVaultImpl: 0x5DeDB0F5587F83798245a53189c1A52437A52475,
            honeyFactoryPythWrapper: 0x7C4d33b026F44E5E6589BaAf7FF38bd93633d58f
        });
    }

    /// @notice Anvil addresses
    function _getAnvilHoneyAddresses() private pure returns (HoneyAddresses memory) {
        return HoneyAddresses({
            honey: 0x442130BDb0eC2e76B1804362b9e9c25bCE299959,
            honeyImpl: 0x36a10E516452BD2A80Bd5F421B0bC69eB0dFBca9,
            honeyFactory: 0xeBF958b3b453f76fBE491a7F3ED29e37a509F530,
            honeyFactoryReader: 0x353F8910914a46b3b971d54A131184fB46B8d7f8,
            honeyFactoryImpl: 0x6178832DAC009EDA2e1D97f158cd94545F49c289,
            honeyFactoryReaderImpl: 0x1eD95AF653E0a540fC61AD8d1C7D2C5271855fD5,
            collateralVaultImpl: 0x149C89732A9e83FDf20CA4AB03A94C3b4eb21C46,
            honeyFactoryPythWrapper: 0x0E870Ae0ecff7036A7d34F9c571794C4ce1C3d62
        });
    }
}
