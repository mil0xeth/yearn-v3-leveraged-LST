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

    function test_main() public {
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
        skip(55 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);
        skip(10 days);


        skip(100 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);

        skip(100 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);

        skip(100 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit / DEC);
        console.log("loss: ", loss / DEC);

        skip(strategy.profitMaxUnlockTime());

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
    }

    function test_main_profitableReport_withMutipleUsers(uint256 _amount, uint16 _divider, uint16 _secondDivider) public {
        setPerformanceFeeToZero(address(strategy));
        uint256 maxDivider = 100000;
        vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount);
        // vm.assume(_profit > minFuzzAmount * maxDivider && _profit < maxFuzzAmount);
        vm.assume(_divider > 0 && _divider < maxDivider);
        vm.assume(_secondDivider > 0 && _secondDivider < maxDivider);

        // profit must be below 100%
        uint256 _profit = _amount / 10;
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        uint256 thirdUserAmount = _amount / _secondDivider;

        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        uint256 strategyTotal = _amount + secondUserAmount + thirdUserAmount;
        checkStrategyTotals(strategy, strategyTotal, strategyTotal, 0);

        // Earn Interest
        skip(1 days);
        // drop some addtional profit
        airdrop(asset, address(strategy), _profit);

        // DONE: implement logic to simulate earning interest.
        skip(30 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, _profit, "!profit"); // profit should be at least airdrop amount
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        //withdraw part of the funds
        vm.prank(user);
        strategy.redeem(_amount / 8, user, user);
        vm.prank(secondUser);
        strategy.redeem(secondUserAmount / 6, secondUser, secondUser);
        vm.prank(thirdUser);
        strategy.redeem(thirdUserAmount / 4, thirdUser, thirdUser);

        // Skip some time, this will earn some profit
        skip(3 days);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit"); // no airdrop so profit can be mininmal
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // withdraw all funds
        console.log("user shares: ", strategy.balanceOf(user));
        console.log("user2 shares: ", strategy.balanceOf(secondUser));
        console.log("user3 shares: ", strategy.balanceOf(thirdUser));
        uint redeemAmount = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(redeemAmount, user, user);
        redeemAmount = strategy.balanceOf(secondUser);
        vm.prank(secondUser);
        strategy.redeem(redeemAmount, secondUser, secondUser);
        redeemAmount = strategy.balanceOf(thirdUser);
        vm.prank(thirdUser);
        strategy.redeem(redeemAmount, thirdUser, thirdUser);
        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount, "!final balance");
        assertGt(asset.balanceOf(secondUser), secondUserAmount, "!final balance");
        assertGt(asset.balanceOf(thirdUser), thirdUserAmount, "!final balance");

        // verify vault is empty
        checkStrategyTotals(strategy, 0, 0, 0);
    }
    
}



interface PotLike {
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
    function pie(address) external view returns (uint256);
}
