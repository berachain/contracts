// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainType } from "../base/Chain.sol";

struct GovernanceAddresses {
    address governance;
    address timelock;
}

abstract contract GovernanceAddressBook {
    GovernanceAddresses internal _governanceAddresses;

    constructor(ChainType chainType) {
        if (chainType == ChainType.Mainnet) {
            _governanceAddresses = _getMainnetGovernanceAddresses();
        } else if (chainType == ChainType.Testnet) {
            _governanceAddresses = _getTestnetGovernanceAddresses();
        } else if (chainType == ChainType.Devnet) {
            _governanceAddresses = _getDevnetGovernanceAddresses();
        } else {
            _governanceAddresses = _getAnvilGovernanceAddresses();
        }
    }

    function _getMainnetGovernanceAddresses() private pure returns (GovernanceAddresses memory) {
        return GovernanceAddresses({
            governance: 0x4f4A5c2194B8e856b7a05B348F6ba3978FB6f6D5,
            timelock: 0xb5f2000b5744f207c931526cAE2134cAa8b6862a
        });
    }

    function _getTestnetGovernanceAddresses() private pure returns (GovernanceAddresses memory) {
        return GovernanceAddresses({
            governance: 0x4f4A5c2194B8e856b7a05B348F6ba3978FB6f6D5,
            timelock: 0xb5f2000b5744f207c931526cAE2134cAa8b6862a
        });
    }

    function _getDevnetGovernanceAddresses() private pure returns (GovernanceAddresses memory) {
        return GovernanceAddresses({
            governance: 0x80e019f82123f7CA82d22add804Df4147F26c851,
            timelock: 0xe72bA011f7F54CEc00E55CD3564deA1eD5CE1766
        });
    }

    function _getAnvilGovernanceAddresses() private pure returns (GovernanceAddresses memory) {
        return GovernanceAddresses({
            governance: 0x2FE2792E8E01b15c4c2186F6F744D71e9885e8fB,
            timelock: 0x08a0d45cF3f3E956B1Ab0341442685edfA2Cb5FB
        });
    }
}
