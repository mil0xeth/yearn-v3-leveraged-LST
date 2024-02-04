pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public override {
        super.setUp();
    }
    /*
    function test_depositAboveMaxSingleTrade() public {
        uint256 _amount = strategy.maxSingleTrade() + 1; //just above maxSingleTrade
        mintAndDepositIntoStrategy(strategy, user, _amount);
    }
    */

    function testFail_withdrawAboveMaxSingleTrade() public {
        uint256 _amount = strategy.maxSingleTrade() + ONE_ASSET; //just above maxSingleTrade
        //mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, user, _amount);
        vm.prank(keeper);
        keeperReport(strategy);
        vm.prank(user);
        userRedeem(strategy, _amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);
    }


    function test_shudownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, 0, _amount);

        vm.prank(keeper);
        keeperReport(strategy);

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        userRedeem(strategy, _amount, user, user);

        assertGe(asset.balanceOf(user)* (MAX_BPS + expectedActivityLossBPS*4)/MAX_BPS, balanceBefore + _amount, "!final balance");
    }

}
