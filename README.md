# AAVE-Delta-Neutral-st-yCRV Strategy for Yearn V3 (foundry)
Strategy collateralizes asset on AAVE (V3) and borrows CRV token to deposit into st-yCRV.

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

## Periphery

To make Strategy writing as simple as possible, a suite of optional 'Periphery Helper' contracts can be inherited by your Strategy to provide standardized and tested functionality for things like swaps. A complete list of the periphery contracts can be viewed here https://github.com/Schlagonia/tokenized-strategy-periphery.


All periphery contracts are optional, and strategists are free to choose if they wish to use them.

### Swappers

In order to make reward swapping as easy and standardized as possible there are multiple swapper contracts that can be inherited by a strategy to inherit pre-built and tested logic for whicher method of reward swapping that is desired. This allows a strategist to only need to set a few global varaibles and then simply use the default syntax of `_swapFrom(tokenFrom, tokenTo, amount, minAmountOut)` to swap any tokens easily during `_totalInvested`.

### APR Oracles

In order for easy integration with Vaults, frontends, debt allocaters etc. There is the option to create an apr oracle contract for your specific strategy that should return the expected apr of the Strategy based on some given debtChange. 


### HealthCheck

In order to prevent automated reports from reporting losses/excessive profits from automated reports that may not be accurate, a strategist can inherit and implement the HealtCheck contract. Using this can assure that a keeper will not call a report that may incorrectly realize incorrect losses or excessive gains. It can cause the report to revert if the gain/loss is outside of the desired bounds and will require manual intervention to assure the strategy is reporting correctly.

NOTE: It is recommended to implement some checks in `_totalInvested` for levereaged or maipulatable strategies that could report incorrect losses due to unforseen circumstances.

### Report Triggers

The expected behavior is that strategies report profits/losses on a set schedule based on their specific `profitMaxUnlockTime` that management can customize. If a custom trigger cycle is desired or extra checks should be added a stategist can create their own customReportTrigger that can be added to the default contract for a specific strategy.

## Testing

Due to the nature of the BaseTokenizedStrategy utilizing an external contract for the majority of its logic, the default interface for any tokenized strategy will not allow proper testing of all functions. Testing of your Strategy should utilize the pre-built [IStrategyInterface](https://github.com/Schlagonia/tokenized-strategy-foundry-mix/blob/master/src/interfaces/IStrategyInterface.sol) interface to cast any deployed strategy through for testing, as seen in the Setup example. You can add any external functions that you add for your specific strategy to this interface to be able to test all functions with one variable. 

Example:

    Strategy _strategy = new Strategy(asset, name);
    IStrategyInterface strategy =  IStrategyInterface(address(_strategy));

Due to the permissionless nature of the tokenized Strategies, all tests are written without integration with any meta vault funding it. While those tests can be added, all V3 vaults utilize the ERC-4626 standard for deposit/withdraw and accounting, so they can be plugged in easily to any number of different vaults with the same `asset.`

Tests run in fork environment, you need to complete the full installation and setup to be able to run these commands.

```sh
make test
```
Run tests with traces (very useful)

```sh
make trace
```
Run specific test contract (e.g. `test/StrategyOperation.t.sol`)

```sh
make test-contract contract=StrategyOperationsTest
```
Run specific test contract with traces (e.g. `test/StrategyOperation.t.sol`)

```sh
make trace-contract contract=StrategyOperationsTest
```

See here for some tips on testing [`Testing Tips`](https://book.getfoundry.sh/forge/tests.html)


When testing on chains other than mainnet you will need to make sure a valid `CAHIN_RPC_URL` for that chain is set in your .env and that chains specific api key is set for `ETHERSCAN_API_KEY`. You will then need to simply adjust the variable that RPCU_URL is set to in the Makefile to match your chain.


#### Errors:

### Deployment

#### Contract Verification

Once the Strategy is fully deployed and verified, you will need to verify the TokenizedStrategy functions. To do this, navigate to the /#code page on etherscan.

1. Click on the `More Options` drop-down menu. 
2. Click "is this a proxy?".
3. Click the "Verify" button.
4. Click "Save". 

This should add all of the external `TokenizedStrategy` functions to the contract interface on Etherscan.

See the ApeWorx [documentation](https://docs.apeworx.io/ape/stable/) and [github](https://github.com/ApeWorX/ape) for more information.
