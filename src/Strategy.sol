// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurve} from "./interfaces/Curve/Curve.sol";
/// @title yearn-v3-LST-WMATIC
/// @author mil0x
/// @notice yearn-v3 Strategy that stakes asset into Liquid Staking Token (LST).
contract Strategy is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;
    address public constant LST = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4; //STMATIC
    address public curve = 0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28; //curve_STMATIC_WMATIC
    uint256 public ASSETID = 1;
    uint256 public LSTID = 0;

    // Parameters    
    uint256 public maxSingleTrade; //maximum amount that should be swapped in one go
    uint256 public swapSlippage; //actual slippage for a trade independent of the depeg; we check with curve oracle for depeg

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_BPS = 100_00;
    uint256 internal constant ASSET_DUST = 100_000_000_000;
    address internal constant gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52; //yearn governance

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        //approvals:
        ERC20(_asset).safeApprove(curve, type(uint256).max);
        ERC20(LST).safeApprove(curve, type(uint256).max);

        maxSingleTrade = 100_000 * 1e18; //maximum amount that should be swapped in one go
        swapSlippage = 8_00; //actual slippage for a trade independent of the depeg; we check with curve oracle for depeg
    }

    //receive() external payable {} //able to receive ETH

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
        ICurve(curve).exchange(ASSETID, LSTID, _amount, _assetToLST(_amount) * (MAX_BPS - swapSlippage) / MAX_BPS); //minAmountOut in LST, account for swapping slippage
    }

    function _assetToLST(uint256 _assetAmount) internal view returns (uint256) {
        if (ASSETID == 0) {
            return _zeroToOne(_assetAmount);
        } else {
            return _oneToZero(_assetAmount);
        }
    }

    function _LSTtoAsset(uint256 _LSTamount) internal view returns (uint256) {
        if (ASSETID == 0) {
            return _oneToZero(_LSTamount);
        } else {
            return _zeroToOne(_LSTamount);
        }
    }

    function _zeroToOne(uint256 _zeroAmount) internal view returns (uint256) {
        return _zeroAmount * WAD / ICurve(curve).price_oracle(); //price_oracle gives One to Zero ratio --> invert
    }

    function _oneToZero(uint256 _oneAmount) internal view returns (uint256) {
        return _oneAmount * ICurve(curve).price_oracle() / WAD; //price_oracle gives One to Zero ratio --> direct
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return maxSingleTrade;
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
        ICurve(curve).exchange(LSTID, ASSETID, _amount, _LSTtoAsset(_amount) * (MAX_BPS - swapSlippage) / MAX_BPS); //account for swapping slippage
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // deposit any loose asset in the strategy
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
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

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        require(msg.sender == gov, "!gov");
        _;
    }

    /// @notice Set the curve router address in case TVL has migrated to a new curve pool. Assign ASSETID and LSTID according to their _curve.coins(ID). Only callable by governance.
    function setCurveRouter(address _curve, uint256 _ASSETID, uint256 _LSTID) external onlyGovernance {
        require(_curve != address(0));
        ERC20(asset).safeApprove(_curve, type(uint256).max);
        ERC20(LST).safeApprove(_curve, type(uint256).max);
        curve = _curve;
        ASSETID = _ASSETID;
        LSTID = _LSTID;
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
