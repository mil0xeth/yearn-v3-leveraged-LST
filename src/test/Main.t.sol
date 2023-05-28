// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import {IAToken} from "../interfaces/Aave/V3/IAtoken.sol";

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

    function test_operation() public {
        //init
        uint256 _amount = 1000e18; //1000 DAI
        uint256 DEC = 1e18; //asset 1e18 for 18 decimals
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
        //aToken amount:
        IAToken aToken = IAToken(strategy.aToken());
        console.log("aToken address: ", address(aToken));
        console.log("aToken balance: ", aToken.balanceOf(address(strategy)) / DEC);
        checkStrategyTotals(strategy, _amount, _amount, 0);
        console.log("balanceAsset: ", strategy.balanceAsset() / DEC);
        console.log("balanceCollateral: ", strategy.balanceCollateral() / DEC);
        console.log("balanceDebt in CRV: ", strategy.balanceCRVDebt());
        //console.log("balanceDebt in Asset: ", strategy.CRVtoAsset(strategy.balanceCRVDebt()));
        console.log("balanceSTYCRV in STCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in CRV: ", strategy.STYCRVtoCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in DAI: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));

        //keeper borrowMore:
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        console.log("profit after first report: ", profit / DEC);
        console.log("loss after first report: ", loss / DEC);
        console.log("balanceAsset: ", strategy.balanceAsset() / DEC);
        console.log("balanceCollateral: ", strategy.balanceCollateral() / DEC);
        console.log("balanceDebt in CRV: ", strategy.balanceCRVDebt());
        //console.log("balanceDebt in Asset: ", strategy.CRVtoAsset(strategy.balanceCRVDebt()));
        console.log("balanceSTYCRV in STCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in CRV: ", strategy.STYCRVtoCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in DAI: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
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
