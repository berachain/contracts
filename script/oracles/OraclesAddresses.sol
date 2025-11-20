// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainType } from "../base/Chain.sol";

struct OraclesAddresses {
    address pythPriceOracle;
    address peggedPriceOracle;
    address rootPriceOracle;
    address extPyth; // Third-party dependencies
}

abstract contract OraclesAddressBook {
    OraclesAddresses internal _oraclesAddresses;

    constructor(ChainType chainType) {
        if (chainType == ChainType.Mainnet) {
            _oraclesAddresses = _getMainnetOraclesAddresses();
        } else if (chainType == ChainType.Testnet) {
            _oraclesAddresses = _getTestnetOraclesAddresses();
        } else if (chainType == ChainType.Devnet) {
            _oraclesAddresses = _getDevnetOraclesAddresses();
        } else {
            _oraclesAddresses = _getAnvilOraclesAddresses();
        }
    }

    function _getMainnetOraclesAddresses() private pure returns (OraclesAddresses memory) {
        return OraclesAddresses({
            pythPriceOracle: 0x5CA67e134c52B1d11E038A5a4eD8Ddcdb1238943,
            peggedPriceOracle: 0xE72FA7893ec375D82a0ff3078920C39D87F8FC2D,
            rootPriceOracle: 0xe641aacDf2055F0D20c9ABc8FeF9dFBc5A68600B,
            extPyth: 0x2880aB155794e7179c9eE2e38200202908C17B43
        });
    }

    function _getTestnetOraclesAddresses() private pure returns (OraclesAddresses memory) {
        return OraclesAddresses({
            pythPriceOracle: 0x5CA67e134c52B1d11E038A5a4eD8Ddcdb1238943,
            peggedPriceOracle: 0xE72FA7893ec375D82a0ff3078920C39D87F8FC2D,
            rootPriceOracle: 0xe641aacDf2055F0D20c9ABc8FeF9dFBc5A68600B,
            extPyth: 0x2880aB155794e7179c9eE2e38200202908C17B43
        });
    }

    function _getDevnetOraclesAddresses() private pure returns (OraclesAddresses memory) {
        return OraclesAddresses({
            pythPriceOracle: 0x8d6864Da39C9Cd4454709Ee55fD383fa2e72200A,
            peggedPriceOracle: 0x969FA953E1554237357571a2Cf04dF717d8c9ca5,
            rootPriceOracle: 0x99F8Ff2f48001FaE858C809b61599013F6f5a3d1,
            extPyth: 0x2880aB155794e7179c9eE2e38200202908C17B43
        });
    }

    function _getAnvilOraclesAddresses() private pure returns (OraclesAddresses memory) {
        return OraclesAddresses({
            pythPriceOracle: 0x4D7c72253b91B083f44ac0415f2D776861258025,
            peggedPriceOracle: 0x0811E041eF374591A01cb49E5030D24b4911287e,
            rootPriceOracle: 0x1EE6c86aeC1307Ef7D1c5144e1A2830BF5bD81Ae,
            extPyth: 0x2880aB155794e7179c9eE2e38200202908C17B43
        });
    }
}
