// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/Lido/ISTETH.sol";
import "../../interfaces/Lido/IWETH.sol";

import {Strategy} from "../../Strategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

import {IPool} from "../../interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "../../interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IPriceOracle} from "../../interfaces/Aave/V3/IPriceOracle.sol";
import {IAToken} from "../../interfaces/Aave/V3/IAToken.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol"; 
import {TokenizedStrategy} from "@tokenized-strategy/TokenizedStrategy.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instancees that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;

    IAToken public aToken;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public user2 = address(5);
    address public user3 = address(6);
    address public user4 = address(7);
    address payable public bucket = payable(0xa840CaD8DbF5504F800Fc6aA4582d841895169E7);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public LST;

    // Address of the real deployed Factory
    address public factory = 0x85E2861b3b1a70c90D28DfEc30CE6E07550d83e9;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;
    uint256 public WAD = 1e18;

    enum Swapper {UNIV3, BALANCER}
    uint256 public ASSET_DUST;
    Strategy.Swapper public swapper;
    address public swapPool;

    bool public useFlashloan;
    address public GOV;

    // Fuzz
    uint256 public maxFuzzAmount = 100000 * 1e18; //1e5 * 1e18;
    uint256 public minFuzzAmount = 1e18;

    uint256 public expectedActivityLossBPS = 500;
    uint256 public expectedActivityLossMultipleUsersBPS = 300;
    uint256 public expectedProfitReductionBPS = 300;
    uint256 public ONE_ASSET;
    uint256 public highProfit;
    uint256 public highLoss;
    uint256 public swapSlippageForHighProfit;
    uint256 public swapSlippageForHighLoss;
    uint256 public swapSlippageForHighLossPool;

    IPool public lendingPool;
    IProtocolDataProvider public protocolDataProvider;


    bytes32 public constant BASE_STRATEGY_STORAGE = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    // Default prfot max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        uint256 mainnetFork = vm.createFork("mainnet");
        uint256 polygonFork = vm.createFork("polygon");
        //uint256 avaxFork = vm.createFork("avax");
        //uint256 optimismFork = vm.createFork("optimism");
        uint256 arbitrumFork = vm.createFork("arbitrum");

        //vm.selectFork(mainnetFork);
        vm.selectFork(polygonFork);
        //vm.selectFork(avaxFork);
        //vm.selectFork(optimismFork);
        //vm.selectFork(arbitrumFork);

        //Fork specific parameters:
        //MAINNET:
        if(vm.activeFork() == mainnetFork) {
            asset = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); //WETH
            ONE_ASSET = 1e18;
            highProfit = 300e18;
            highLoss = 300e18;
            swapSlippageForHighProfit = 5_00;
            swapSlippageForHighLoss = 5_00;
        }
        //ARBITRUM:
        if(vm.activeFork() == arbitrumFork) {
            asset = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); //WETH
            ASSET_DUST = 4e14; 
            LST = 0x5979D7b546E38E414F7E9822514be443A4800529; //WSTETH
            lendingPool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD); //aavev3 arbitrum
            protocolDataProvider = IProtocolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654); //aavev3 arbitrum
            swapper = Strategy.Swapper.UNIV3;
            swapPool = 0x9791d590788598535278552EEcD4b211bFc790CB; //wsteth weth pool
            useFlashloan = true;
            GOV = 0xC4ad0000E223E398DC329235e6C497Db5470B626; //??????

            ONE_ASSET = 1e18;
            highProfit = 300e18;
            highLoss = 300e18;
            swapSlippageForHighProfit = 5_00;
            swapSlippageForHighLoss = 5_00;
            swapSlippageForHighLossPool = 5_00;
        }
        //Polygon:
        if(vm.activeFork() == polygonFork) {
            asset = ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); //WMATIC
            ASSET_DUST = 1e17;
            LST = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;
            lendingPool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD); //aavev3 polygon
            protocolDataProvider = IProtocolDataProvider(0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654); //aavev3 polygon
            swapper = Strategy.Swapper.BALANCER;
            swapPool = 0xf0ad209e2e969EAAA8C882aac71f02D8a047d5c2; //stmatic wmatic pool
            useFlashloan = false;
            GOV = 0xC4ad0000E223E398DC329235e6C497Db5470B626;

            ONE_ASSET = 1e18;
            highProfit = 50_000e18;
            highLoss = 50_000e18;
            swapSlippageForHighProfit = 10_00;
            swapSlippageForHighLoss = 15_00;
            swapSlippageForHighLossPool = 25_00;
        }

        // Set decimals
        decimals = asset.decimals();

        // Deploy strategy and set variables
        // we save the strategy as a IStrategyInterface to give it the needed interface
        strategy = IStrategyInterface(address(new Strategy(address(asset), ASSET_DUST, LST, address(protocolDataProvider), swapper, swapPool, useFlashloan, GOV, "Tokenized Strategy")));

        // set keeper
        strategy.setKeeper(keeper);
        // set treasury
        strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        strategy.setPendingManagement(management);
        // Accept mangagement.
        vm.prank(management);
        strategy.acceptManagement();
        
        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");

        (address _aToken, , ) = protocolDataProvider.getReserveTokensAddresses(LST);
        aToken = IAToken(_aToken);

        vm.prank(management);
        strategy.setMaxSingleTrade(100e6*ONE_ASSET);
        vm.prank(management);
        strategy.setMaxSingleWithdraw(100e6*ONE_ASSET);
        vm.prank(management);
        strategy.setProfitLimitRatio(1e18); //we don't want to revert in tests on too high profits from airdrops
        vm.prank(management);
        strategy.setLossLimitRatio(20_00);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(address(asset), _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertEq(_strategy.totalAssets(), _totalAssets, "!totalAssets");
        assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(address _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = ERC20(_asset).balanceOf(_to);
        deal(_asset, _to, balanceBefore + _amount);
    }

    function keeperReport(IStrategyInterface _strategy) public returns (uint256 profit, uint256 loss) {
        uint256 beforeLoanToValue = _strategy.currentLoanToValue();

        vm.prank(keeper);
        (profit, loss) = _strategy.report();

        assertLe(_strategy.balanceOfAsset(), 100_000, "ERR: keeperReport: balanceOfAsset > DUST");
        if (maxDepositableCollateral() > 100_000) {
            assertLe(_strategy.balanceOfLST(), 100_000, "ERR: keeperReport: balanceOfLST > DUST");
        }
        
        uint256 afterLoanToValue = _strategy.currentLoanToValue();
        if (beforeLoanToValue < strategy.windLoanToValue()) { //wind:
            assertLt(beforeLoanToValue, afterLoanToValue, "ERR: keeperReport: beforeLoanToValue < beforeLoanToValue");    
            assertApproxEqAbs(afterLoanToValue, _strategy.targetLoanToValue(), 2e16, "ERR: keeperReport: afterLoanToValue != targetLoanToValue");
        } else if (beforeLoanToValue > strategy.unwindLoanToValue()) { //unwind:
            assertLe(afterLoanToValue, beforeLoanToValue, "ERR: keeperReport: afterLoanToValue < beforeLoanToValue");
            assertApproxEqAbs(afterLoanToValue, _strategy.targetLoanToValue(), 1e16, "ERR: keeperReport: afterLoanToValue != targetLoanToValue");
        }
    }

    function userRedeem(IStrategyInterface _strategy, uint256 _amount, address _user, address _userDummy) public {
        assertEq(_user, _userDummy, "ERR: _userDummy");
        uint256 beforeAssetBalance = _strategy.balanceOfAsset();
        uint256 beforeLST = _strategy.balanceOfLST();
        uint256 beforeLoanToValue = _strategy.currentLoanToValue();

        vm.prank(_user);
        _strategy.redeem(_amount, _user, _user);

        uint256 afterLoanToValue = _strategy.currentLoanToValue();

        if (afterLoanToValue != 0) {
            assertApproxEqAbs(afterLoanToValue, beforeLoanToValue, 5e15, "ERR: userRedeem: afterLoanToValue != beforeLoanToValue");

            assertLe(_strategy.balanceOfAsset(), beforeAssetBalance, "ERR: userRedeem: balanceOfAsset > DUST");
            assertLe(_strategy.balanceOfLST(), beforeLST, "ERR: userRedeem: balanceOfLST > DUST");
        }
    }

    function maxDepositableCollateral() public view returns (uint256) {
        uint256 negligibleAmountOfAsset = 0;
        (, uint256 supplyCap) = protocolDataProvider.getReserveCaps(LST);
        uint256 maximumAmount = supplyCap * WAD;
        uint256 currentAmount = IAToken(aToken).totalSupply();
        if (currentAmount + negligibleAmountOfAsset >= maximumAmount) {
            return 0;
        } else {
            return maximumAmount - currentAmount - negligibleAmountOfAsset;
        }
    }

    function checkStrategyInvariantsAfterReport(IStrategyInterface _strategy) public {
    }

    function checkStrategyInvariantsAfterRedeem(IStrategyInterface _strategy) public {
    }

    function getExpectedProtocolFee(
        uint256 _amount,
        uint16 _fee
    ) public view returns (uint256) {
        uint256 timePassed = block.timestamp - strategy.lastReport();

        return (_amount * _fee * timePassed) / MAX_BPS / 31_556_952;
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    // For easier calculations we may want to set the performance fee
    // to 0 in some tests which is underneath the minimum. So we do it manually.
    function setPerformanceFeeToZero(address _strategy) public {
        bytes32 slot;
        TokenizedStrategy.StrategyData storage S = _strategyStorage();

        assembly {
            // Perf fee is stored in the 12th slot of the Struct.
            slot := add(S.slot, 12)
        }

        // Performance fee is packed in a slot with other variables so we need
        // to maintain the same variables packed in the slot

        // profitMaxUnlock time is a uint32 at the most significant spot.
        bytes32 data = bytes4(
            uint32(IStrategyInterface(_strategy).profitMaxUnlockTime())
        );
        // Free up space for the uint16 of performancFee
        data = data >> 16;
        // Store 0 in the performance fee spot.
        data |= bytes2(0);
        // Shit 160 bits for an address
        data = data >> 160;
        // Store the strategies peformance fee recipient
        data |= bytes20(
            uint160(IStrategyInterface(_strategy).performanceFeeRecipient())
        );
        // Shift the remainder of padding.
        data = data >> 48;

        // Manually set the storage slot that holds the perfomance fee to 0
        vm.store(_strategy, slot, data);
    }

    function _strategyStorage()
        internal
        pure
        returns (TokenizedStrategy.StrategyData storage S)
    {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = BASE_STRATEGY_STORAGE;
        assembly {
            S.slot := slot
        }
    }
}
