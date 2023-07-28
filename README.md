# Liquid Staking Token Staker (LST) for yearn V3
Strategy stakes token into LST, e.g. MATIC into stMATIC and collect yields.
Supports: stETH, stMatic, MaticX.

This repo uses [Foundry](https://book.getfoundry.sh/) for tests.

For a more complete overview of how the Tokenized Strategies work please visit the [TokenizedStrategy Repo](https://github.com/yearn/tokenized-strategy).

## How to start

### Requirements
First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Set your environment Variables

Sign up for [Infura](https://infura.io/) and generate an API key and copy your RPC url. Store it in the `ETH_RPC_URL` environment variable.
NOTE: you can use other services.

Use .env file
  1. Make a copy of `.env.example`
  2. Add the values for `ETH_RPC_URL`, `ETHERSCAN_API_KEY` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.


### Build the project.

```sh
make build
```

Run tests
```sh
make test
```
