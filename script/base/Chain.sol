// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

enum ChainType {
    Unknown,
    Anvil,
    Mainnet,
    Testnet,
    Devnet
}

library ChainHelper {
    uint256 private constant MAINNET_CHAIN_ID = 80_094;
    uint256 private constant TESTNET_CHAIN_ID = 80_069;
    uint256 private constant DEVNET_CHAIN_ID = 80_087;
    uint256 private constant ANVIL_CHAIN_ID = 31_337;

    function getType() internal view returns (ChainType) {
        uint256 chainID = block.chainid;

        if (chainID == MAINNET_CHAIN_ID) {
            return ChainType.Mainnet;
        } else if (chainID == TESTNET_CHAIN_ID) {
            return ChainType.Testnet;
        } else if (chainID == DEVNET_CHAIN_ID) {
            return ChainType.Devnet;
        } else if (chainID == ANVIL_CHAIN_ID) {
            return ChainType.Anvil;
        } else {
            return ChainType.Unknown;
        }
    }

    function getLabel(ChainType chainType) internal pure returns (string memory) {
        if (chainType == ChainType.Mainnet) {
            return "Mainnet";
        } else if (chainType == ChainType.Testnet) {
            return "Testnet";
        } else if (chainType == ChainType.Devnet) {
            return "Devnet";
        } else if (chainType == ChainType.Anvil) {
            return "Anvil";
        } else {
            return "Unknown";
        }
    }
}
