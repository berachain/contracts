// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";

import { BeraChef, IBeraChef } from "src/pol/rewards/BeraChef.sol";
import { BGT } from "src/pol/BGT.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { RewardVaultFactory } from "src/pol/rewards/RewardVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { BeaconRootsHelper, Distributor } from "src/pol/rewards/Distributor.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { BGTFeeDeployer } from "src/pol/BGTFeeDeployer.sol";
import { POLDeployer } from "src/pol/POLDeployer.sol";
import { WBERA } from "src/WBERA.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BeaconDepositMock } from "test/mock/pol/BeaconDepositMock.sol";
import { BGTIncentiveDistributor } from "src/pol/rewards/BGTIncentiveDistributor.sol";

abstract contract POLTest is Test, Create2Deployer {
    uint256 internal constant TEST_BGT_PER_BLOCK = 5 ether;
    uint64 internal constant DISTRIBUTE_FOR_TIMESTAMP = 1_234_567_890;
    uint256 internal constant PAYOUT_AMOUNT = 1e18;
    uint64 internal constant HISTORY_BUFFER_LENGTH = 8191;
    uint64 internal constant ZERO_VALIDATOR_PUBKEY_G_INDEX = 3_254_554_418_216_960;
    uint64 internal constant PROPOSER_INDEX_G_INDEX = 9;
    address internal governance = makeAddr("governance");
    // beacon deposit address defined in the contract.
    address internal beaconDepositContract = 0x4242424242424242424242424242424242424242;
    address internal operator = makeAddr("operator");
    address internal bgtIncentiveReceiverManager = makeAddr("bgtIncentiveReceiverManager");

    struct ValData {
        bytes32 beaconBlockRoot;
        uint64 index;
        bytes pubkey;
        bytes32[] proposerIndexProof;
        bytes32[] pubkeyProof;
    }

    ValData internal valData;

    BeraChef internal beraChef;
    BGT internal bgt;
    BGTStaker internal bgtStaker;
    BlockRewardController internal blockRewardController;
    RewardVaultFactory internal factory;
    FeeCollector internal feeCollector;
    Distributor internal distributor;
    POLDeployer internal polDeployer;
    BGTFeeDeployer internal feeDeployer;
    WBERA internal wbera;
    address internal bgtIncentiveDistributor;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // read in proof data
        valData = abi.decode(
            stdJson.parseRaw(
                vm.readFile(string.concat(vm.projectRoot(), "/test/pol/fixtures/validator_data_proofs.json")), "$"
            ),
            (ValData)
        );

        deployPOL(governance);

        wbera = new WBERA();
        deployBGTFees(governance);

        vm.startPrank(governance);
        bgt.setMinter(address(blockRewardController));
        bgt.setStaker(address(bgtStaker));
        bgt.whitelistSender(address(distributor), true);

        factory.setBGTIncentiveDistributor(bgtIncentiveDistributor);
        beraChef.setCommissionChangeDelay(2 * 8191);
        beraChef.setMaxWeightPerVault(1e4);

        // change rewards duration to 3 days in BGTStaker
        bgtStaker.setRewardsDuration(3 days);

        // add native token to BGT for backing
        vm.deal(address(bgt), 100_000 ether);
        vm.stopPrank();
    }

    function deployBGT(address owner) internal {
        bgt = new BGT();
        bgt.initialize(owner);
    }

    function deployBGTIncentiveDistributor(address owner) internal {
        address bgtIncentiveDistributorImpl = deployWithCreate2(0, type(BGTIncentiveDistributor).creationCode);
        bgtIncentiveDistributor = (deployProxyWithCreate2(bgtIncentiveDistributorImpl, 0));
        BGTIncentiveDistributor(bgtIncentiveDistributor).initialize(owner);
        bytes32 managerRole = BGTIncentiveDistributor(bgtIncentiveDistributor).MANAGER_ROLE();
        vm.prank(owner);
        BGTIncentiveDistributor(bgtIncentiveDistributor).grantRole(managerRole, bgtIncentiveReceiverManager);
    }

    function deployBGTFees(address owner) internal {
        feeDeployer = new BGTFeeDeployer(address(bgt), owner, address(wbera), 0, 0, PAYOUT_AMOUNT);
        bgtStaker = feeDeployer.bgtStaker();
        feeCollector = feeDeployer.feeCollector();
    }

    function deployPOL(address owner) internal {
        deployBGT(owner);
        deployBGTIncentiveDistributor(owner);

        // deploy the beacon deposit contract at the address defined in the contract.
        deployCodeTo("BeaconDepositMock.sol", beaconDepositContract);
        // set the operator of the validator.
        BeaconDepositMock(beaconDepositContract).setOperator(valData.pubkey, operator);

        polDeployer = new POLDeployer(address(bgt), owner, 0, 0, 0, 0);
        beraChef = polDeployer.beraChef();
        blockRewardController = polDeployer.blockRewardController();
        factory = polDeployer.rewardVaultFactory();
        distributor = polDeployer.distributor();
    }
}
