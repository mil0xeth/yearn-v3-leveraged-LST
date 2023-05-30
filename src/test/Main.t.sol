// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import "../interfaces/maker/IMaker.sol";

contract MainTest is Setup {

    PotLike public pot = PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);

    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation() public {
        //init
        uint256 _amount = 1000e18; //1000 DAI
        uint256 DEC = 1e18; //asset 1e18 for 18 decimals
        uint256 profit;
        uint256 loss;
        DEC = 1;
        console.log("asset: ", asset.symbol());
        console.log("amount:", _amount / DEC);
        //user funds:
        airdrop(asset, user, _amount);
        assertEq(asset.balanceOf(user), _amount, "!totalAssets");
        //user deposit:
        depositIntoStrategy(strategy, user, _amount);
        assertEq(asset.balanceOf(user), 0, "user balance after deposit =! 0");
        assertEq(strategy.totalAssets(), _amount, "strategy.totalAssets() != _amount after deposit");
        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);

        // Earn Interest
        skip(1 days);

        console.log("skip strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);



/*
        //user 2, user 3 funds:
        airdrop(asset, user2, _amount);
        depositIntoStrategy(strategy, user2, _amount);
        airdrop(asset, user3, _amount);
        depositIntoStrategy(strategy, user3, _amount);

        //airdrop:
        uint256 toAirdrop = 10e18; //10 DAI
        airdrop(asset, address(strategy), toAirdrop);
        console.log("airdrop strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) / DEC);

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);

        //user4 deposit:
        airdrop(asset, user4, _amount);
        depositIntoStrategy(strategy, user4, _amount);

        skip(strategy.profitMaxUnlockTime()/2);

        // Withdraw all funds
        vm.prank(user4);
        strategy.redeem(_amount, user4, user4);
        console.log("redeem strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);
        console.log("asset.balanceOf(user4): ", asset.balanceOf(user4) / DEC);
*/
/*

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("redeem strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) / DEC);

        console.log("profitMaxUnlockTime: ", strategy.profitMaxUnlockTime());

        //skip(strategy.profitMaxUnlockTime());
*/

/*
        // Report profit / loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);



        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) / DEC);



        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets() / DEC);
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() / DEC);
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("balanceUpdatedDSR: ", strategy.balanceUpdatedDSR() / DEC);
        console.log("balanceDSR(): ", strategy.balanceDSR() / DEC);
        console.log("pot.pie(): ", pot.pie(address(strategy)) / DEC);
        console.log("daiBalance: ", asset.balanceOf(address(strategy)) / DEC);
        console.log("assetBalance: ", strategy.balanceAsset() / DEC);
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) / DEC);

        skip(strategy.profitMaxUnlockTime());
*/

    }
/*
    function test_fuzz_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);
    }
*/
}


interface PotLike {
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
    function pie(address) external view returns (uint256);
}
