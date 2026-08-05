// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainType } from "../base/Chain.sol";

struct BUSDAddresses {
    address busd;
    address busdImpl;
    address busdFactory;
    address busdFactoryReader;
    address busdFactoryImpl;
    address busdFactoryReaderImpl;
    address collateralVaultImpl;
    address busdFactoryPythWrapper;
}

abstract contract BUSDAddressBook {
    BUSDAddresses internal _busdAddresses;

    constructor(ChainType chainType) {
        if (chainType == ChainType.Mainnet) {
            _busdAddresses = _getMainnetBUSDAddresses();
        } else if (chainType == ChainType.Testnet) {
            _busdAddresses = _getTestnetBUSDAddresses();
        } else if (chainType == ChainType.Devnet) {
            _busdAddresses = _getDevnetBUSDAddresses();
        } else {
            _busdAddresses = _getAnvilBUSDAddresses();
        }
    }

    /// @notice Mainnet addresses
    /// @dev Some of this contracts were deployed with a different context, hence their adddress should not be updated
    /// even if the predicted ones are different.
    function _getMainnetBUSDAddresses() private pure returns (BUSDAddresses memory) {
        return BUSDAddresses({
            busd: 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce,
            busdImpl: 0x4B66208F2867eE655d2aef73c8f04799270D2c27,
            busdFactory: 0xA4aFef880F5cE1f63c9fb48F661E27F8B4216401,
            busdFactoryReader: 0x285e147060CDc5ba902786d3A471224ee6cE0F91,
            busdFactoryImpl: 0x4Cce25f697923603264B6ce039CC7147592D66e2,
            busdFactoryReaderImpl: 0xe70B4e9147f2e6DcaA7619dD617451877e9fDD6f,
            collateralVaultImpl: 0xAa4f2Bc7a06c89BEAB5125D82e25D4166b4a4681,
            busdFactoryPythWrapper: 0x2D9a98012a0d64d50C64021fE49d70e46aE95e30
        });
    }

    /// @notice Bepolia addresses
    /// @dev Some of this contracts were deployed with a different context, hence their adddress should not be updated
    /// even if the predicted ones are different.
    function _getTestnetBUSDAddresses() private pure returns (BUSDAddresses memory) {
        return BUSDAddresses({
            busd: 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce,
            busdImpl: 0xE8FdFFeC66076d695228fe6fBBD5B5333C0e350D,
            busdFactory: 0xA4aFef880F5cE1f63c9fb48F661E27F8B4216401,
            busdFactoryReader: 0x285e147060CDc5ba902786d3A471224ee6cE0F91,
            busdFactoryImpl: 0x65918Ebe5c1705520db69C3CA7De7F038B7ae965,
            busdFactoryReaderImpl: 0xDAb123631660Ea393b53E97CB30336e539413F90,
            collateralVaultImpl: 0xE3689043e7F860FbC0c814839cd7dF5022223172,
            busdFactoryPythWrapper: 0x55f70d8B47d6cF4478945CBF1CaB7d4b28ec34fE
        });
    }

    /// @notice Devnet addresses
    function _getDevnetBUSDAddresses() private pure returns (BUSDAddresses memory) {
        return BUSDAddresses({
            busd: 0x4475bdcd6F2Ded26Ea5074beb862271f2141f696,
            busdImpl: 0x6f9b591f026b6b4A4ad0D903cc97Cda67381afAe,
            busdFactory: 0x2AA7F988284fD04cE83b27d017B89731c67d8F67,
            busdFactoryReader: 0xf1CF3467C9508dfa6D1197F5359419856B3A3300,
            busdFactoryImpl: 0x665100D9b055C24A4aB019e0374eAe6E67154B39,
            busdFactoryReaderImpl: 0x414F206A71BCdaFDDF5BD726bDddB453bC88b5B6,
            collateralVaultImpl: 0x5DeDB0F5587F83798245a53189c1A52437A52475,
            busdFactoryPythWrapper: 0x8712D71d12294DE7a7fd8636dAF71B960853a6fD
        });
    }

    /// @notice Anvil addresses
    function _getAnvilBUSDAddresses() private pure returns (BUSDAddresses memory) {
        return BUSDAddresses({
            busd: 0xbd9859Edaaf6383a3769c1Ffa7aBFBF80E3326d2,
            busdImpl: 0xF6a8765a1ddf3Bf7dB050DA1c9c28b5913bee520,
            busdFactory: 0xF6e0C4E70E6c5B3A8986Fb8D448842eAF5Fb4a96,
            busdFactoryReader: 0xD9bE61E5cE08A0D4c4c9906c4aeB2Ac9Dbf4C43C,
            busdFactoryImpl: 0x6763D0A7af2b53538D7043D7B089F0D41056E155,
            busdFactoryReaderImpl: 0xDDbA312ffF582cB4B3a45d02829611a843893bA4,
            collateralVaultImpl: 0x149C89732A9e83FDf20CA4AB03A94C3b4eb21C46,
            busdFactoryPythWrapper: 0x131D7bB79D3928506B698eCFF88A51e55e3ccee3
        });
    }
}
