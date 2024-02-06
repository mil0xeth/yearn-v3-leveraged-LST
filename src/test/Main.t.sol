// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import "../interfaces/maker/IMaker.sol";

contract MainTest is Setup {

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

    function test_main() public {
        //init
        uint256 _amount = 50e18;
        uint256 profit;
        uint256 loss;
        console.log("asset: ", asset.symbol());
        console.log("amount:", _amount );
        console.log("LST:", LST);
        //user funds:
        console.log("user", user);
        airdrop(address(asset), user, _amount);
        assertEq(asset.balanceOf(user), _amount, "!totalAssets");
        //user deposit:
        depositIntoStrategy(strategy, user, _amount);
        assertEq(strategy.totalAssets(), _amount, "strategy.totalAssets() != _amount after deposit");
        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets() );
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() );
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() );
        console.log("strategy.balanceOfAsset() after deposit", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("strategy.currentLoanToValue AFTER DEPOSIT:", strategy.currentLoanToValue());

        // Report profit / loss
        (profit, loss) = keeperReport(strategy);
        console.log("profit: ", profit );
        console.log("loss: ", loss );
        console.log("strategy.balanceOfAsset()", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("strategy.balanceOfCollateral();", strategy.balanceOfCollateral());
        console.log("strategy.balanceOfDebt();", strategy.balanceOfDebt());
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());

        skip(strategy.profitMaxUnlockTime());

        //user deposit:
        airdrop(address(asset), user, _amount);
        assertEq(asset.balanceOf(user), _amount, "!totalAssets");
        depositIntoStrategy(strategy, user, _amount);
        assertEq(asset.balanceOf(user), 0, "user balance after deposit =! 0");
        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets() );
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt() );
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle() );
        console.log("strategy.balanceOfAsset() after deposit", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());

        // Report profit / loss
        (profit, loss) = keeperReport(strategy);
        console.log("profit: ", profit );
        console.log("loss: ", loss );
        console.log("strategy.balanceOfAsset()", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("strategy.balanceOfCollateral();", strategy.balanceOfCollateral());
        console.log("strategy.balanceOfDebt();", strategy.balanceOfDebt());
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());

        //skip(strategy.profitMaxUnlockTime());

        console.log("strategy.balanceOfAsset()", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("strategy.balanceOfCollateral();", strategy.balanceOfCollateral());
        console.log("strategy.balanceOfDebt();", strategy.balanceOfDebt());
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());

        skip(200 days);
        console.log("SKIPPED 200 DAYS", strategy.currentLoanToValue());
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit );
        console.log("loss: ", loss );
        console.log("strategy.balanceOfAsset()", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("strategy.balanceOfCollateral();", strategy.balanceOfCollateral());
        console.log("strategy.balanceOfDebt();", strategy.balanceOfDebt());
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());

        // Withdraw half the funds
        userRedeem(strategy, _amount, user, user); 
        console.log("redeem strategy.totalAssets() after redeem: ", strategy.totalAssets() );
        console.log("strategy.totalDebt() after redeem: ", strategy.totalDebt() );
        console.log("strategy.totalIdle() after redeem: ", strategy.totalIdle() );
        console.log("assetBalance: ", asset.balanceOf(address(strategy)) );
        console.log("assetBalance: ", strategy.balanceOfAsset() );
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) );
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());

        // Withdraw other half
        uint256 sharesRemaining = strategy.balanceOf(user);
        userRedeem(strategy, sharesRemaining, user, user); 
        console.log("redeem strategy.totalAssets() after redeem: ", strategy.totalAssets() );
        console.log("strategy.totalDebt() after redeem: ", strategy.totalDebt() );
        console.log("strategy.totalIdle() after redeem: ", strategy.totalIdle() );
        console.log("assetBalance: ", asset.balanceOf(address(strategy)) );
        console.log("assetBalance: ", strategy.balanceOfAsset() );
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) );
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());


        console.log("strategy.balanceOfAsset()", strategy.balanceOfAsset());
        console.log("strategy.balanceOfLST()", strategy.balanceOfLST());
        console.log("strategy.balanceOfCollateral();", strategy.balanceOfCollateral());
        console.log("strategy.balanceOfDebt();", strategy.balanceOfDebt());
        console.log("strategy.currentLoanToValue()", strategy.currentLoanToValue());
        console.log("strategy.totalSupply()", strategy.totalSupply());
    }
}
