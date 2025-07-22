# Berachain Contracts

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ bun run lint
```

### Test

Run the tests:

```sh
$ forge test
```

Generate test coverage and output result to the terminal:

```sh
$ bun run test:coverage
```

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ bun run test:coverage:report
```

## ABI Management

This repository includes automated ABI management that syncs contract ABIs to a checkout of[`doc-abis`](https://github.com/berachain/doc-abis) repository, expected to be found at `../doc-abis`, next to the `contracts` checkout.

### Commands

```sh
# Sync all ABI files (update existing + create missing, excludes test/mock contracts)
$ npm run abis:sync
```

### Adding New Contracts

ABIs are automatically organized into directories:

- **`core/`** - Protocol contracts (BeraChef, BGT, RewardVault, etc.)
- **`gov/`** - Governance contracts (BerachainGovernance, Timelock)
- **`bex/`** - BEX/Balancer contracts (interfaces starting with `I`)
- **`misc/`** - Other contracts (ERC20, utilities)

To add a new contract category, update the `directoryMapping` in [`manage-abis.js`](./manage-abis.js).

## Related Efforts

- [abigger87/femplate](https://github.com/abigger87/femplate)
- [cleanunicorn/ethereum-smartcontract-template](https://github.com/cleanunicorn/ethereum-smartcontract-template)
- [foundry-rs/forge-template](https://github.com/foundry-rs/forge-template)
- [FrankieIsLost/forge-template](https://github.com/FrankieIsLost/forge-template)

## License

This project is licensed under BUSL 1.1.

## Solstat

Follow instructions to install [solstat](https://github.com/0xKitsune/solstat) locally and run. Currently, named
parameters in mappings causes solstat to panic and is unable to produce the solstat_report.md
([issue](https://github.com/0xKitsune/solstat/issues/87)).
