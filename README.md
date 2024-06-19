## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```


### How to get it started:

Here are the forge install commands:
```
forge install OpenZeppelin/openzeppelin-contracts@v4.9.5
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.9.5
forge install redstone-finance/redstone-oracles-monorepo
```

Here are is the remappings file:

```
@openzeppelin/=lib/openzeppelin-contracts/
@redstone-finance/evm-connector/=lib/redstone-oracles-monorepo/packages/evm-connector/
```
