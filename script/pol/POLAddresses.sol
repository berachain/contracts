// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ChainType } from "../base/Chain.sol";

struct POLAddresses {
    address beaconDeposit;
    address wbera;
    address bgt;
    address beraChef;
    address beraChefImpl;
    address blockRewardController;
    address blockRewardControllerImpl;
    address distributor;
    address distributorImpl;
    address rewardVaultFactory;
    address rewardVaultFactoryImpl;
    address rewardVaultImpl;
    address bgtStaker;
    address bgtStakerImpl;
    address feeCollector;
    address feeCollectorImpl;
    address bgtIncentiveDistributor;
    address bgtIncentiveDistributorImpl;
    address bgtIncentiveFeeCollector;
    address bgtIncentiveFeeCollectorImpl;
    address wberaStakerVault;
    address wberaStakerVaultImpl;
    address wberaStakerVaultWithdrawalRequest;
    address wberaStakerVaultWithdrawalRequestImpl;
    address rewardVaultHelper;
    address rewardVaultHelperImpl;
    address rewardAllocatorFactory;
    address rewardAllocatorFactoryImpl;
}

abstract contract POLAddressBook {
    POLAddresses internal _polAddresses;

    constructor(ChainType chainType) {
        if (chainType == ChainType.Mainnet) {
            _polAddresses = _getMainnetPOLAddresses();
        } else if (chainType == ChainType.Testnet) {
            _polAddresses = _getTestnetPOLAddresses();
        } else if (chainType == ChainType.Devnet) {
            _polAddresses = _getDevnetPOLAddresses();
        } else {
            _polAddresses = _getAnvilPOLAddresses();
        }
    }

    /// @notice Mainnet addresses
    /// @dev Some of this contracts were deployed with a different context, hence their adddress should not be updated
    /// even if the predicted ones are different.
    function _getMainnetPOLAddresses() private pure returns (POLAddresses memory) {
        return POLAddresses({
            beaconDeposit: 0x4242424242424242424242424242424242424242, // From genesis files
            wbera: 0x6969696969696969696969696969696969696969, // From genesis files
            bgt: 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba,
            beraChef: 0xdf960E8F3F19C481dDE769edEDD439ea1a63426a,
            beraChefImpl: 0x45F31D709518ddBD93d537bE99facc0b0869363A,
            blockRewardController: 0x1AE7dD7AE06F6C58B4524d9c1f816094B1bcCD8e,
            blockRewardControllerImpl: 0x971aF0c15E15F1F31ff60C6Ed2c2234B88D5d25a,
            distributor: 0xD2f19a79b026Fb636A7c300bF5947df113940761,
            distributorImpl: 0xaEB85B186CC8e305282ad7777D7A11ad76329426,
            rewardVaultFactory: 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8,
            rewardVaultFactoryImpl: 0x6b75ab5860B9129C58bdb01b8194dd1CBc428cac,
            rewardVaultImpl: 0x68DFD1c244Fc65Ca57967E269BD0112aF0eC2184,
            bgtStaker: 0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6,
            bgtStakerImpl: 0xDD7FA46a1a735DBD7E7eD4B1928176D28002e205,
            feeCollector: 0x7Bb8DdaC7FbE3FFC0f4B3c73C4F158B06CF82650,
            feeCollectorImpl: 0x0fE7B2A78f8c239569ec22cdbdb472694afc289c,
            bgtIncentiveDistributor: 0x77DA09bC82652f9A14d1b170a001e759640298e6,
            bgtIncentiveDistributorImpl: 0xa0170DBDe24E92F0d3140CC119E8c51b85BE2DC6,
            bgtIncentiveFeeCollector: 0x1984Baf659607Cc5f206c55BB3B00eb3E180190B,
            bgtIncentiveFeeCollectorImpl: 0x6B2847e6eE63A08204707AaF0C46fAa0F78215fC,
            wberaStakerVault: 0x118D2cEeE9785eaf70C15Cd74CD84c9f8c3EeC9a,
            wberaStakerVaultImpl: 0x281Fe772A0f25A81e825c7a5697BABaFeE0D0eF2,
            wberaStakerVaultWithdrawalRequest: 0x30e47fd0452a14Caf18A0444cb6f35eaCaC899DA,
            wberaStakerVaultWithdrawalRequestImpl: 0x9d77351A50eba1D50A77B1b86b94b7bD9f42f216,
            rewardVaultHelper: 0xEe233a69A36Db7fC10E03e921D90DEC52Cdce6e2,
            rewardVaultHelperImpl: 0xa64951392198b4c9739d336Da22F853d8a66a8C5,
            rewardAllocatorFactory: 0xc8FD9a3fB3Dad4C22c9F8Cfa7cecC318A667A791,
            rewardAllocatorFactoryImpl: 0x7e80F890Ac3752711BC40fE18FDbbe23BEB88f2B
        });
    }

    /// @notice Bepolia addresses
    /// @dev Some of this contracts were deployed with a different context, hence their adddress should not be updated
    /// even if the predicted ones are different.
    function _getTestnetPOLAddresses() private pure returns (POLAddresses memory) {
        return POLAddresses({
            beaconDeposit: 0x4242424242424242424242424242424242424242, // From genesis files
            wbera: 0x6969696969696969696969696969696969696969, // From genesis files
            bgt: 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba,
            beraChef: 0xdf960E8F3F19C481dDE769edEDD439ea1a63426a,
            beraChefImpl: 0x3f86340DC9F3C69D421f1CF6a7E271a436D6c6D4,
            blockRewardController: 0x1AE7dD7AE06F6C58B4524d9c1f816094B1bcCD8e,
            blockRewardControllerImpl: 0x401479c852286F702536613dA8De237401621161,
            distributor: 0xD2f19a79b026Fb636A7c300bF5947df113940761,
            distributorImpl: 0x0a52Be37b6A5C666CFee37cbA7787B2dd815cCD0,
            rewardVaultFactory: 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8,
            rewardVaultFactoryImpl: 0xa6f4899209302f363E863ED8E7aCD76b1d8998E1,
            rewardVaultImpl: 0xC87Bb594Cd9d80Dc9E5ab26582913EE5f6eB2BB6,
            bgtStaker: 0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6,
            bgtStakerImpl: 0x66B872cC8B01269E20E5E5aB05C2F7A1198A67Ce,
            feeCollector: 0x7Bb8DdaC7FbE3FFC0f4B3c73C4F158B06CF82650,
            feeCollectorImpl: 0x6ca4930Efc5cb995D83e2607571A3b2060532f75,
            bgtIncentiveDistributor: 0x77DA09bC82652f9A14d1b170a001e759640298e6,
            bgtIncentiveDistributorImpl: 0x7E71C51F367f5f4A9D08151f7C24a2503Fa1A844,
            bgtIncentiveFeeCollector: 0x1984Baf659607Cc5f206c55BB3B00eb3E180190B,
            bgtIncentiveFeeCollectorImpl: 0x0B703418f96FC308C3Fd1cc3CD9F85A4dD65B862,
            wberaStakerVault: 0x118D2cEeE9785eaf70C15Cd74CD84c9f8c3EeC9a,
            wberaStakerVaultImpl: 0x83aa9046028eA3Bc506Fd01b19b24c15E800558d,
            wberaStakerVaultWithdrawalRequest: 0x30e47fd0452a14Caf18A0444cb6f35eaCaC899DA,
            wberaStakerVaultWithdrawalRequestImpl: 0x1a1b50F511feb89a92DA0ACB2732cfebfB66B096,
            rewardVaultHelper: 0xEe233a69A36Db7fC10E03e921D90DEC52Cdce6e2,
            rewardVaultHelperImpl: 0x3026AD38f797B311F9B0d35891eD1D2C35b4F40C,
            rewardAllocatorFactory: 0x7f09Cf6958631513aF0400488F65c7B5c0313F52,
            rewardAllocatorFactoryImpl: 0xA3b40aB9c6f7B45625cBD81a1F05027f5507Ee0d
        });
    }

    /// @notice Devnet addresses
    function _getDevnetPOLAddresses() private pure returns (POLAddresses memory) {
        return POLAddresses({
            beaconDeposit: 0x4242424242424242424242424242424242424242, // From genesis files
            wbera: 0x6969696969696969696969696969696969696969, // From genesis files
            bgt: 0xEE0BD9569e41fA26A79305Fc31a663986Deb79FB,
            beraChef: 0x11D327E93F251e6cCE267e392CdA9eEF8Ff9099B,
            beraChefImpl: 0xB1610b3f7C539e79933EC7cde7FE0dc79f556a2D,
            blockRewardController: 0x4A2452Fd7e9FCA389d98063c5C3A8FC63838E451,
            blockRewardControllerImpl: 0xf1774D66392999268a40c8c9Df1708f220662aba,
            distributor: 0x9dD639638B46899CED46ef58b3A3c21E9feF9d7c,
            distributorImpl: 0x2b564641cC5E3dfac81eE337D512f8313a6067DF,
            rewardVaultFactory: 0xb6C6e3A4aBf3777ffccB01d0a8581daAc07CaAEf,
            rewardVaultFactoryImpl: 0x3199Ea83F2731b74d77F7A989cE3bDF785779304,
            rewardVaultImpl: 0xB9a8323d504994EC9dD864887D29F21e6eDbaDf2,
            bgtStaker: 0xb3EFeD697e5A10568E65452d5fAd4CFcF057e457,
            bgtStakerImpl: 0xE2fC2F9AC9e4988187f7A37B161fd042E3E0A4F8,
            feeCollector: 0x750791868bcf30654543165bfc9BD1da1E071870,
            feeCollectorImpl: 0xca68B6742c78Fac8276082eb74E4532B8E24887d,
            bgtIncentiveDistributor: 0x6DC1E455571937a1A579090c8f879A4431E169b8,
            bgtIncentiveDistributorImpl: 0x507B0b5781c747E73Fd0dd670D77166a5cc232f3,
            bgtIncentiveFeeCollector: 0xc3322E5886CdA15b51b1cbe5A8b5668F9C6Ad72E,
            bgtIncentiveFeeCollectorImpl: 0x47F69e8b85D43Ed6e3a278FCC11bd2210Fb47d74,
            wberaStakerVault: 0x39091E2a8472Bc3364F59dFF620c9163AA27F397,
            wberaStakerVaultImpl: 0x76ca749157a8f2627F1189eA26C27460b1C1Ce01,
            wberaStakerVaultWithdrawalRequest: 0xa48b32DE980349893de3C2Eb6cC2C5505E8A53c6,
            wberaStakerVaultWithdrawalRequestImpl: 0xC99dbe0679AAa9c95B1C1d00d8D25a3EA5Bf552a,
            rewardVaultHelper: 0x41BE38f22F6D04D2D8A2e6b13fB71B8a4b8B4bD3,
            rewardVaultHelperImpl: 0xA88C548a1160fc28e9DA6F91cfA2Ef76dEBFAE70,
            rewardAllocatorFactory: 0xF9451D2Ca42C703bc86Ca8aE76336527EAA5d63A,
            rewardAllocatorFactoryImpl: 0xf6503F1c149bB6c12f1F25c500c580335578A520
        });
    }

    /// @notice Anvil addresses
    function _getAnvilPOLAddresses() private pure returns (POLAddresses memory) {
        return POLAddresses({
            beaconDeposit: 0x4242424242424242424242424242424242424242, // From genesis files
            wbera: 0x6969696969696969696969696969696969696969, // From genesis files
            bgt: 0xe804A615556BB2c4B530057DdBc77E5385957a25,
            beraChef: 0x4898c5fb3af0Be5E709e35E75800a5E313BF6e8a,
            beraChefImpl: 0x043a056462860e874A3eC25349613F5d165cb176,
            blockRewardController: 0xf1aDf7a50773FF65c7cE8662A309F8e277Cd7Ec6,
            blockRewardControllerImpl: 0x147585c9E870f1CE7F3320A30ff2E43410463e58,
            distributor: 0x046e3BeED5090A8f6EF88eeFD1a1877360560F71,
            distributorImpl: 0xEdE384457a2D271307ef0F6C83077fc86253F4d1,
            rewardVaultFactory: 0x5D280c8F2227A594De61902fE4154Ea669163742,
            rewardVaultFactoryImpl: 0x589e95A46B566d2d011314b4f209716f266f774D,
            rewardVaultImpl: 0x62C114DD46829ADc7ACf98D9ef5ecaC91b2f53E2,
            bgtStaker: 0x57C4b599Ef3D476cC2bc9eb494542db546F764f0,
            bgtStakerImpl: 0x409aCA0227Dc0B097c05E97c46499011EdB6F48b,
            feeCollector: 0x2B7686Aff4595Ca1EbF9Ff6168C039b6A980222E,
            feeCollectorImpl: 0xa5D7a877297B31da1A3D0CcfdfC41D1C27428d36,
            bgtIncentiveDistributor: 0x4200d596bE35b7AB8aD0c17E04b11c60F7AC2938,
            bgtIncentiveDistributorImpl: 0xE6B7C8391eeB8b82EEdb2d015fcEaef4eC16c7D8,
            bgtIncentiveFeeCollector: 0xBE4f441CcE02268Ca29C85DeBB558002E1133b25,
            bgtIncentiveFeeCollectorImpl: 0xdaD62bf78690430eC65C764A640a1674473D1A68,
            wberaStakerVault: 0x806A948acc78DA018b76aE8afabB6B71Ab95D3DB,
            wberaStakerVaultImpl: 0xFA75d7639987bC2153218A0EC81b7B06BfF5DaE4,
            wberaStakerVaultWithdrawalRequest: 0x8bbFF3F485B1263CFb1960e7505FC6456dC14D5B,
            wberaStakerVaultWithdrawalRequestImpl: 0x2C7231a59EeC62658D7ca01f1d4A557bda1029A3,
            rewardVaultHelper: 0x3dD313F3d08fAD4220CA0f153A0b984932567716,
            rewardVaultHelperImpl: 0x19DA32A86BFfee117527c34243ccba7B3d155b65,
            rewardAllocatorFactory: 0x36886B62Cbfd2d7278C3F045B44f29E42153Ea89,
            rewardAllocatorFactoryImpl: 0x9aC5cB10145085cf84a8291243F5e832C62534A2
        });
    }
}
