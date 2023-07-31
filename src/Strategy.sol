// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/Chainlink/AggregatorInterface.sol";
import {IBalancer, IBalancerPool} from "./interfaces/Balancer/IBalancer.sol";

/// @title yearn-v3-LST-WMATIC
/// @author mil0x
/// @notice yearn-v3 Strategy that stakes asset into Liquid Staking Token (LST).
contract Strategy is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;
    address public constant LST = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4; //STMATIC
    // Use chainlink oracle to check LST price
    AggregatorInterface public chainlinkOracleAsset = AggregatorInterface(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0); //matic/usd
    AggregatorInterface public chainlinkOracleLST = AggregatorInterface(0x97371dF4492605486e23Da797fA68e55Fc38a13f); //stmatic/usd
    address internal constant BALANCER = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public pool = 0xf0ad209e2e969EAAA8C882aac71f02D8a047d5c2; //stmatic wmatic pool

    // Parameters    
    uint256 public maxSingleTrade; //maximum amount that should be swapped in one go
    uint256 public swapSlippage; //actual slippage for a trade

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_BPS = 100_00;
    uint256 internal constant ASSET_DUST = 100000;
    address internal constant GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52; //yearn governance

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        //approvals:
        ERC20(_asset).safeApprove(BALANCER, type(uint256).max);
        ERC20(LST).safeApprove(BALANCER, type(uint256).max);

        maxSingleTrade = 1_000_000 * 1e18; //maximum amount that should be swapped in one go
        swapSlippage = 2_00; //actual slippage for a trade
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        _stake(_amount);
    }

    function _stake(uint256 _amount) internal {
        if (_amount < ASSET_DUST) {
            return;
        }
        swapBalancer(address(asset), LST, _amount, _assetToLST(_amount) * (MAX_BPS - swapSlippage) / MAX_BPS); //minAmountOut in LST, account for swapping slippage
    }

    function _assetToLST(uint256 _assetAmount) internal view returns (uint256) {
        uint256 assetPrice = uint256(chainlinkOracleAsset.latestAnswer()) * 1e10; //convert decimals from chainlink to LST
        uint256 LSTprice = uint256(chainlinkOracleLST.latestAnswer()) * 1e10; //convert decimals from chainlink to LST
        return _assetAmount * assetPrice / LSTprice;
    }

    function _LSTtoAsset(uint256 _LSTamount) internal view returns (uint256) {
        uint256 assetPrice = uint256(chainlinkOracleAsset.latestAnswer()) * 1e10; //convert decimals from chainlink to LST
        uint256 LSTprice = uint256(chainlinkOracleLST.latestAnswer()) * 1e10; //convert decimals from chainlink to LST
        return _LSTamount * LSTprice / assetPrice;
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return _balanceAsset() + maxSingleTrade;
    }
    
    function _freeFunds(uint256 _assetAmount) internal override {
        //Unstake LST amount proportional to the shares redeemed:
        uint256 LSTamountToUnstake = _balanceLST() * _assetAmount / TokenizedStrategy.totalAssets();
        _unstake(LSTamountToUnstake);
        uint256 assetBalance = _balanceAsset();
        if (assetBalance > _assetAmount) { //did we swap too much?
            _stake(assetBalance - _assetAmount); //in case we swapped too much to satisfy _assetAmount, swap rest back to LST
        }
    }

    function _unstake(uint256 _amount) internal {
        swapBalancer(LST, address(asset), _amount, _LSTtoAsset(_amount) * (MAX_BPS - swapSlippage) / MAX_BPS); //minAmountOut in asset, account for swapping slippage
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // deposit any loose asset in the strategy
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > ASSET_DUST && !TokenizedStrategy.isShutdown()) {
            _stake(Math.min(maxSingleTrade, looseAsset));
        }
        // Total assets of the strategy:
        _totalAssets = _balanceAsset() + _LSTtoAsset(_balanceLST());
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceLST() internal view returns (uint256){
        return ERC20(LST).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the amount of asset the strategy holds.
    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }
    
    /// @notice Returns the amount of staked asset in liquid staking token (LST) the strategy holds.
    function balanceLST() external view returns (uint256) {
        return _balanceLST();
    }

    /// @notice Set the maximum amount of asset that can be withdrawn or can be moved by keepers in a single transaction. This is to avoid unnecessarily large slippages and incentivizes staggered withdrawals.
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyManagement {
        maxSingleTrade = _maxSingleTrade;
    }

    /// @notice Set the maximum slippage in basis points (BPS) to accept when swapping asset <-> staked asset in liquid staking token (LST).
    function setSwapSlippage(uint256 _swapSlippage) external onlyManagement {
        require(_swapSlippage <= MAX_BPS);
        swapSlippage = _swapSlippage;
    }

    function swapBalancer(address _tokenIn, address _tokenOut, uint256 _amount, uint256 _minAmountOut) internal {
        IBalancer.SingleSwap memory singleSwap;
        singleSwap.poolId = IBalancerPool(pool).getPoolId();
        singleSwap.kind = 0;
        singleSwap.assetIn = _tokenIn;
        singleSwap.assetOut = _tokenOut;
        singleSwap.amount = _amount;
        IBalancer.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = true;
        funds.recipient = payable(this);
        funds.toInternalBalance = false;
        IBalancer(BALANCER).swap(singleSwap, funds, _minAmountOut, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }

    /// @notice Set the balancer pool address in case TVL has migrated to a new balancer pool. Only callable by governance.
    function setPool(address _pool) external onlyGovernance {
        require(_pool != address(0));
        pool = _pool;
    }

    /// @notice Set the chainlink oracle address to a new address. Only callable by governance.
    function setChainlinkOracle(address _chainlinkOracleAsset, address _chainlinkOracleLST) external onlyGovernance {
        require(_chainlinkOracleAsset != address(0));
        require(_chainlinkOracleLST != address(0));
        chainlinkOracleAsset = AggregatorInterface(_chainlinkOracleAsset);
        chainlinkOracleLST = AggregatorInterface(_chainlinkOracleLST);
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY:
    //////////////////////////////////////////////////////////////*/

    // Emergency withdraw LST amount and swap. Best to do this in steps.
    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = Math.min(_amount, _balanceLST());
        _unstake(_amount);
    }
}
