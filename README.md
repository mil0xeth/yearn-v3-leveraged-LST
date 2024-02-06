# Leveraged Liquid Staking Token (LST) Strategy for yearn V3
yearn-v3 strategy leveraging a Liquid Staking Token (LST) on AAVE for leveraged yield.
Supports: wstETH on all chains. stMATIC on Polygon.


### Requirements
First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).

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
