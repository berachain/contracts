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
    address incentivesCollector;
    address incentivesCollectorImpl;
    address wberaStakerVault;
    address wberaStakerVaultImpl;
    address wberaStakerVaultWithdrawalRequest;
    address wberaStakerVaultWithdrawalRequestImpl;
    address rewardVaultHelper;
    address rewardVaultHelperImpl;
    address rewardAllocatorFactory;
    address rewardAllocatorFactoryImpl;
    address lstStakerVaultFactory;
    address lstStakerVaultFactoryImpl;
    address lstStakerVaultImpl;
    address lstStakerVaultWithdrawalRequestImpl;
    address dedicatedEmissionStreamManager;
    address dedicatedEmissionStreamManagerImpl;
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
            beraChefImpl: 0x7BE46e21Af81E432228E7ae15DfAA409E4ea211e,
            blockRewardController: 0x1AE7dD7AE06F6C58B4524d9c1f816094B1bcCD8e,
            blockRewardControllerImpl: 0x6341356004D27821CBBd9b8554F0aF53FB39776C,
            distributor: 0xD2f19a79b026Fb636A7c300bF5947df113940761,
            distributorImpl: 0xABc4e807C2664eBBa530D2A4348b3151A4E05b8f,
            rewardVaultFactory: 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8,
            rewardVaultFactoryImpl: 0xF96dB70f2F87dB141beEbCF4eDE97a3f13153E31,
            rewardVaultImpl: 0x40CF72ec06B66b0454682e2ee07Ab84022ea00d5,
            bgtStaker: 0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6,
            bgtStakerImpl: 0xDD7FA46a1a735DBD7E7eD4B1928176D28002e205,
            feeCollector: 0x7Bb8DdaC7FbE3FFC0f4B3c73C4F158B06CF82650,
            feeCollectorImpl: 0x0fE7B2A78f8c239569ec22cdbdb472694afc289c,
            bgtIncentiveDistributor: 0x77DA09bC82652f9A14d1b170a001e759640298e6,
            bgtIncentiveDistributorImpl: 0x5c5BfeFddB6f6A51F1D24A6a99F3BeA53eE59F29,
            incentivesCollector: 0x1984Baf659607Cc5f206c55BB3B00eb3E180190B,
            incentivesCollectorImpl: 0x16565CCEc1b6782cf06C9fab051a1299036d1ddB,
            wberaStakerVault: 0x118D2cEeE9785eaf70C15Cd74CD84c9f8c3EeC9a,
            wberaStakerVaultImpl: 0x657EC58fDc6CebBDB78d74f814b1C5fA3C0423B1,
            wberaStakerVaultWithdrawalRequest: 0x30e47fd0452a14Caf18A0444cb6f35eaCaC899DA,
            wberaStakerVaultWithdrawalRequestImpl: 0x9d77351A50eba1D50A77B1b86b94b7bD9f42f216,
            rewardVaultHelper: 0xEe233a69A36Db7fC10E03e921D90DEC52Cdce6e2,
            rewardVaultHelperImpl: 0x8cA1678AA2eC74bA62a3B9a0f4335846fd32D3c8,
            rewardAllocatorFactory: 0xc8FD9a3fB3Dad4C22c9F8Cfa7cecC318A667A791,
            rewardAllocatorFactoryImpl: 0x7e80F890Ac3752711BC40fE18FDbbe23BEB88f2B,
            lstStakerVaultFactory: 0xc41bbD6695AB6bdc6D04701b15f4CE5EbA2e2500,
            lstStakerVaultFactoryImpl: 0x4ad7D50440370E277F523330458e7eFFF0C6cfb1,
            lstStakerVaultImpl: 0x805c3BB9f74fF0d14eF401f0Fd986713fA521C68,
            lstStakerVaultWithdrawalRequestImpl: 0x5Df9799bd804E0f0001Df62d34c0026CFeb5890c,
            dedicatedEmissionStreamManager: 0x813dCdBa9197947792985c866cE98D6739cA821A,
            dedicatedEmissionStreamManagerImpl: 0x59F977fB8BbB820F4E3f09Dcd9dAE851b5d08462
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
            beraChefImpl: 0xb0857802D9B91ffD797562627f4801BA080c512b,
            blockRewardController: 0x1AE7dD7AE06F6C58B4524d9c1f816094B1bcCD8e,
            blockRewardControllerImpl: 0x3e6286bEeB457fBDc6C1218215be12c2B1a6D9B2,
            distributor: 0xD2f19a79b026Fb636A7c300bF5947df113940761,
            distributorImpl: 0x65Ccba6221503173Ff984Bd326F412Ef584AFf13,
            rewardVaultFactory: 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8,
            rewardVaultFactoryImpl: 0x16E955dc6e8d1B379853a25142658077477c9E1f,
            rewardVaultImpl: 0xa1a85743d500D5976e511062E62f2cB1E7E40A99,
            bgtStaker: 0x44F07Ce5AfeCbCC406e6beFD40cc2998eEb8c7C6,
            bgtStakerImpl: 0x66B872cC8B01269E20E5E5aB05C2F7A1198A67Ce,
            feeCollector: 0x7Bb8DdaC7FbE3FFC0f4B3c73C4F158B06CF82650,
            feeCollectorImpl: 0x6ca4930Efc5cb995D83e2607571A3b2060532f75,
            bgtIncentiveDistributor: 0xb0d005Fe83E3F1ec876C1a64700c5F0d6265d9E3,
            bgtIncentiveDistributorImpl: 0x4AA432E9a3FD5dC58146Ef231ff346364E36Cc6D,
            incentivesCollector: 0x1984Baf659607Cc5f206c55BB3B00eb3E180190B,
            incentivesCollectorImpl: 0xf79936BFF041a489CE7bE62cc46bbbdf86003689,
            wberaStakerVault: 0x118D2cEeE9785eaf70C15Cd74CD84c9f8c3EeC9a,
            wberaStakerVaultImpl: 0x68348D7c5973bB932c108F03C04C16900827Fc14,
            wberaStakerVaultWithdrawalRequest: 0x30e47fd0452a14Caf18A0444cb6f35eaCaC899DA,
            wberaStakerVaultWithdrawalRequestImpl: 0x1a1b50F511feb89a92DA0ACB2732cfebfB66B096,
            rewardVaultHelper: 0xEe233a69A36Db7fC10E03e921D90DEC52Cdce6e2,
            rewardVaultHelperImpl: 0x9104D6f5201EC22fa3DBb3CCEEd6eABBcD1D306d,
            rewardAllocatorFactory: 0x7f09Cf6958631513aF0400488F65c7B5c0313F52,
            rewardAllocatorFactoryImpl: 0xA3b40aB9c6f7B45625cBD81a1F05027f5507Ee0d,
            lstStakerVaultFactory: 0xAf10B532cCC25B26a8e28913D5C4056a77e7a178,
            lstStakerVaultFactoryImpl: 0x211acBf8a0241F7671909cc645314010fC7F6aAe,
            lstStakerVaultImpl: 0x49CA7e596d5F1B96d1B8274B2e6eFFe92ffD53ec,
            lstStakerVaultWithdrawalRequestImpl: 0x78e151F4e599eC1EebDa2563536BDa14498E2f21,
            dedicatedEmissionStreamManager: 0xfe83d31669b52B7a619119Bc71805fD29eeEB9Dd,
            dedicatedEmissionStreamManagerImpl: 0xC4333904Cf08E6715e69A11E3999900522A1D0E6
        });
    }

    /// @notice Devnet addresses
    function _getDevnetPOLAddresses() private pure returns (POLAddresses memory) {
        return POLAddresses({
            beaconDeposit: 0x4242424242424242424242424242424242424242, // From genesis files
            wbera: 0x6969696969696969696969696969696969696969, // From genesis files
            bgt: 0xEE0BD9569e41fA26A79305Fc31a663986Deb79FB,
            beraChef: 0xD93EB81ff6d6D6a67b60edaE2cf8B5E95Ec47467,
            beraChefImpl: 0xaBE258a826B1fbD00eA0ea3D766a891133B3d93c,
            blockRewardController: 0xe96aD3b5Ea4763B66979d1D76028227bb5CF1951,
            blockRewardControllerImpl: 0x68Ee183142A289a1D1059647fFA905256BE45C7E,
            distributor: 0xEFBA19B83712c6FF15e8bDeB624aB223A1b89af6,
            distributorImpl: 0xa2F64452D137c50A85E78b6dE610a427bf659322,
            rewardVaultFactory: 0xcd47e10A495920C45c12964E7A0d1dc78F0eFfA1,
            rewardVaultFactoryImpl: 0x9c045882Ecd359c9B8e0E707E94Aa13CE797a594,
            rewardVaultImpl: 0xD4718Aaf0a3C341961b67660175D0a0EE68E32dE,
            bgtStaker: 0xb3EFeD697e5A10568E65452d5fAd4CFcF057e457,
            bgtStakerImpl: 0xE2fC2F9AC9e4988187f7A37B161fd042E3E0A4F8,
            feeCollector: 0x750791868bcf30654543165bfc9BD1da1E071870,
            feeCollectorImpl: 0xca68B6742c78Fac8276082eb74E4532B8E24887d,
            bgtIncentiveDistributor: 0x20CA52119499531EF4ac7e83a35Bf1C505538E74,
            bgtIncentiveDistributorImpl: 0x2b9308e4a09F8BEEab2860D255A1a635B8E9FBCF,
            incentivesCollector: 0x2F375FcEa0C162b22a70099D36A01263B681f42b,
            incentivesCollectorImpl: 0xe0aFf6182F9A6E97D423C197fCF2D21b304ac015,
            wberaStakerVault: 0x0651f7834678e19BAf01de086864240DE4FfBE45,
            wberaStakerVaultImpl: 0x7571c17da478022fa3C4C8eD646B282E930F4C67,
            wberaStakerVaultWithdrawalRequest: 0xa48b32DE980349893de3C2Eb6cC2C5505E8A53c6,
            wberaStakerVaultWithdrawalRequestImpl: 0xC99dbe0679AAa9c95B1C1d00d8D25a3EA5Bf552a,
            rewardVaultHelper: 0xd1D259eb84A04df03a32aF7BA6609939D41e10b3,
            rewardVaultHelperImpl: 0x515163711122a14b58f9bba67AEC941BdA00f964,
            rewardAllocatorFactory: 0xF9451D2Ca42C703bc86Ca8aE76336527EAA5d63A,
            rewardAllocatorFactoryImpl: 0xf6503F1c149bB6c12f1F25c500c580335578A520,
            lstStakerVaultFactory: 0x0C9a4C3B7557bb1bED8Cc93Ee11A460220D209e3,
            lstStakerVaultFactoryImpl: 0x3522D0aA63813F5b2987FeEA8Be045E4d399c1aF,
            lstStakerVaultImpl: 0xBADD53A592FC22125D82dC8252D7F7C834fbDAf7,
            lstStakerVaultWithdrawalRequestImpl: 0xED868a9F16b8F715A9fBfE3b9ff4e096B35C7E74,
            dedicatedEmissionStreamManager: 0x469a8410f1417Df9114C7bA7F7846FBE184f9f21,
            dedicatedEmissionStreamManagerImpl: 0x8f28bB60CA6dAF8267276Cc8b4FD389BF5E8b717
        });
    }

    /// @notice Anvil addresses
    function _getAnvilPOLAddresses() private pure returns (POLAddresses memory) {
        return POLAddresses({
            beaconDeposit: 0x4242424242424242424242424242424242424242, // From genesis files
            wbera: 0x6969696969696969696969696969696969696969, // From genesis files
            bgt: 0xe804A615556BB2c4B530057DdBc77E5385957a25,
            beraChef: 0x4898c5fb3af0Be5E709e35E75800a5E313BF6e8a,
            beraChefImpl: 0xa8399eA9bb56B02838294003cddF8e6933fC3B57,
            blockRewardController: 0xf1aDf7a50773FF65c7cE8662A309F8e277Cd7Ec6,
            blockRewardControllerImpl: 0xE16dc304d1aF660A03e618F4948f84042aaEE03c,
            distributor: 0x046e3BeED5090A8f6EF88eeFD1a1877360560F71,
            distributorImpl: 0x7C1810322A453074A1Eb3cd7Ebeb79dE66598378,
            rewardVaultFactory: 0x5D280c8F2227A594De61902fE4154Ea669163742,
            rewardVaultFactoryImpl: 0xe4CaF94A74916cc59E99d4258ae59D2766Abb3b5,
            rewardVaultImpl: 0x0eEBC5ef4AEbB2752E69aFd8e201B1751B13EB46,
            bgtStaker: 0x57C4b599Ef3D476cC2bc9eb494542db546F764f0,
            bgtStakerImpl: 0x409aCA0227Dc0B097c05E97c46499011EdB6F48b,
            feeCollector: 0x2B7686Aff4595Ca1EbF9Ff6168C039b6A980222E,
            feeCollectorImpl: 0xa5D7a877297B31da1A3D0CcfdfC41D1C27428d36,
            bgtIncentiveDistributor: 0xf015eeC023E2Db26D2aa99D84b372E215bd59B65,
            bgtIncentiveDistributorImpl: 0x36a91B80a4f74FE7cfeddF0fc24959d04b89203A,
            incentivesCollector: 0xF158F72596415078803dcC0B8BF7723b0dA5Fcf6,
            incentivesCollectorImpl: 0x319dE2A3Ab9D8F42548F439ABbb4CC4c20F3B489,
            wberaStakerVault: 0x806A948acc78DA018b76aE8afabB6B71Ab95D3DB,
            wberaStakerVaultImpl: 0xEBf7759047f1027B4cC9de0211d611e23841C1e1,
            wberaStakerVaultWithdrawalRequest: 0x8bbFF3F485B1263CFb1960e7505FC6456dC14D5B,
            wberaStakerVaultWithdrawalRequestImpl: 0x2C7231a59EeC62658D7ca01f1d4A557bda1029A3,
            rewardVaultHelper: 0x3dD313F3d08fAD4220CA0f153A0b984932567716,
            rewardVaultHelperImpl: 0xF1F828f1AdE86896bD77e18833581fC52fc2982A,
            rewardAllocatorFactory: 0x36886B62Cbfd2d7278C3F045B44f29E42153Ea89,
            rewardAllocatorFactoryImpl: 0x9aC5cB10145085cf84a8291243F5e832C62534A2,
            lstStakerVaultFactory: 0x31b5Cf9a4F89cEE50a779E95B6b8e6a1D7E4E058,
            lstStakerVaultFactoryImpl: 0xC7acFFe09e857170aFAbBAF27B982dC4f0F5eaBe,
            lstStakerVaultImpl: 0xC891E5dfE7982c99F1eF5aD36f08FCE03652300c,
            lstStakerVaultWithdrawalRequestImpl: 0xAe88Db65a31E4D23Ddb75b6c64F24Ae26ef098E7,
            dedicatedEmissionStreamManager: 0x8a3EB29D2E634FA10F70496BDA230b65f73f1dF1,
            dedicatedEmissionStreamManagerImpl: 0x43e01220C871eE26706F65f2Ba443c0a50ae424A
        });
    }
}
