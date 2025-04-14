// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LibClone } from "solady/src/utils/LibClone.sol";

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { BeaconRoots } from "src/libraries/BeaconRoots.sol";
import { Mock4788BeaconRoots } from "@mock/pol/Mock4788BeaconRoots.sol";

import { RewardVault } from "src/pol/rewards/RewardVault.sol";
import { BerachainGovernance, InitialGovernorParameters } from "src/gov/BerachainGovernance.sol";
import { TimeLock } from "src/gov/TimeLock.sol";
import "../../gov/GovernanceBase.t.sol";

/// @title POLGasSimulationSimple
/// @dev This contract simulates the Proof of Liquidity (POL) gas consumption and the governance mechanism involved.
/// It integrates with a governance system, simulating real-world operations such as proposal creation, voting,
/// and execution within a blockchain governance framework.
contract POLGasSimulationSimple is GovernanceBaseTest {
    bytes32 internal proof; // Store cryptographic proof
    bytes internal signature; // Signature corresponding to the proof
    uint256 internal signerPrivateKey = 0xabc123; // Private key for simulated signer, for test purposes only
    address internal signer; // Address of the signer
    uint64 internal lastProcessedTimestamp = DISTRIBUTE_FOR_TIMESTAMP; // Last processed timestamp

    /// @dev Sets up the environment for each test case. This includes deploying and initializing
    /// governance-related contracts and configuring the initial state required for subsequent tests.
    function setUp() public virtual override {
        // Read in proof data.
        valData = abi.decode(
            stdJson.parseRaw(
                vm.readFile(string.concat(vm.projectRoot(), "/test/pol/fixtures/validator_data_proofs.json")), "$"
            ),
            (ValData)
        );

        // Mock calls to BeaconRoots.ADDRESS to use our mock contract.
        vm.etch(BeaconRoots.ADDRESS, address(new Mock4788BeaconRoots()).code);
        Mock4788BeaconRoots mockBeaconRoots = Mock4788BeaconRoots(BeaconRoots.ADDRESS);
        mockBeaconRoots.setIsTimestampValid(true);
        mockBeaconRoots.setMockBeaconBlockRoot(valData.beaconBlockRoot);

        // Deploying governance logic via an ERC1967 proxy
        gov = BerachainGovernance(payable(LibClone.deployERC1967(address(new BerachainGovernance()))));
        governance = address(gov);

        // Deploy a new TimelockController instance through an ERC1967 proxy
        timelock = TimeLock(payable(LibClone.deployERC1967(address(new TimeLock()))));

        // Grant necessary roles for the governance to interact with the timelock
        address[] memory proposers = new address[](1);
        proposers[0] = address(governance);
        address[] memory executors = new address[](1);
        executors[0] = address(governance);
        // self administration
        timelock.initialize(12 hours, proposers, executors, address(0));

        // Deploy and initialize POL-related contracts
        deployPOL(address(timelock));
        wbera = new WBERA();
        deployBGTFees(address(timelock));

        // NOTE: for gov.getVotes to work, the block timestamp must be a realistic one (greater than zero).
        vm.warp(1 days);

        // Provide initial tokens for testing
        deal(address(bgt), address(this), 100_000_000_000 ether);
        InitialGovernorParameters memory params = InitialGovernorParameters({
            proposalThreshold: 1e9,
            quorumNumeratorValue: 10,
            votingDelay: uint48(5400),
            votingPeriod: uint32(5400)
        });
        gov.initialize(IVotes(address(bgt)), timelock, params);

        // Delegate tokens to self to allow for governance actions
        bgt.delegate(address(this));

        // Advance time and blocks to simulate real-world passage of time
        vm.warp(100 days);
        vm.roll(100);

        // Setup proposal actions, encoded call data for governance actions
        address[] memory targets = new address[](9);
        targets[0] = address(blockRewardController);
        targets[1] = address(blockRewardController);
        targets[2] = address(blockRewardController);
        targets[3] = address(blockRewardController);
        targets[4] = address(bgt);
        targets[5] = address(beraChef);
        targets[6] = address(beraChef);
        targets[7] = address(bgt);
        targets[8] = address(factory);

        bytes[] memory calldatas = new bytes[](9);
        calldatas[0] = abi.encodeCall(BlockRewardController.setRewardRate, (5 ether));
        calldatas[1] = abi.encodeCall(BlockRewardController.setMinBoostedRewardRate, (5 ether));
        calldatas[2] = abi.encodeCall(BlockRewardController.setBoostMultiplier, (3 ether));
        calldatas[3] = abi.encodeCall(BlockRewardController.setRewardConvexity, (0.5 ether));
        calldatas[4] = abi.encodeCall(BGT.whitelistSender, (address(distributor), true));
        calldatas[5] = abi.encodeCall(BeraChef.setRewardAllocationBlockDelay, (0));
        calldatas[6] = abi.encodeCall(BeraChef.setMaxWeightPerVault, (1e4));
        calldatas[7] = abi.encodeCall(BGT.setMinter, (address(blockRewardController)));
        calldatas[8] =
            abi.encodeCall(RewardVaultFactory.setBGTIncentiveDistributor, (address(bgtIncentiveDistributor)));

        // Create and execute governance proposals
        governanceHelper(targets, calldatas);

        // Setup and manage reward vaults
        RewardVault[] memory vaults = createVaults(1);

        // Add incentives to the vault
        addIncentives(vaults, 1);

        // Prepare signature verification simulation
        signer = vm.addr(signerPrivateKey);
        proof = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", abi.encodePacked(valData.pubkey, block.number))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, proof);
        signature = abi.encodePacked(r, s, v);
    }

    /// @dev Tests the gas consumption of POL distribution logic under normal operation conditions
    /// relative to the gas limit of an Arbitrum block.
    // @notice 355396 GAS takes up 1.11% of Arbitrum block gas limit
    function testGasPOLDistribution() public {
        validateAndDistribute(proof, signature, abi.encode(valData.pubkey, block.number - 1));
    }

    /// @dev Simulate not yet implemented signature verification function of Prover
    function validateAndDistribute(
        bytes32 _proof,
        bytes memory _signature,
        bytes memory data
    )
        public
        returns (address validatorAddress, uint256 extractedBlockNumber)
    {
        (validatorAddress, extractedBlockNumber) = abi.decode(data, (address, uint256));

        require(ECDSA.recover(_proof, _signature) == signer, "POLGasSimulationSimple: Invalid signature");

        deal(address(bgt), address(bgt).balance + 100 ether); // simulate native token distribution
        distributor.distributeFor(
            lastProcessedTimestamp, valData.index, valData.pubkey, valData.proposerIndexProof, valData.pubkeyProof
        );
        lastProcessedTimestamp++;

        return (validatorAddress, extractedBlockNumber);
    }
}
