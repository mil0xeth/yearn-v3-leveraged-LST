// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "./interfaces/Yearn/IVault.sol";

import {IAToken} from "./interfaces/Aave/V3/IAToken.sol";
import {IVariableDebtToken} from "./interfaces/Aave/V3/IVariableDebtToken.sol";
import {IStakedAave} from "./interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "./interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";
import {IPriceOracle} from "./interfaces/Aave/V3/IPriceOracle.sol";

import {ICurve} from "./interfaces/Curve/Curve.sol";

// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract Strategy is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    uint256 public LTVborrowLessNOW = 74e16;
    uint256 public LTVborrowLess = 72e16;
    uint256 public LTVtarget = 70e16;
    uint256 public LTVborrowMore = 68e16;

    //yearn
    address public YCRV = 0xFCc5c47bE19d06BF83eB04298b026F81069ff65b;
    address public STYCRV = 0x27B5739e22ad9033bcBf192059122d163b60349D;
    
    //aave
    IProtocolDataProvider public constant protocolDataProvider = IProtocolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);
    IPool public lendingPool;
    IRewardsController public rewardsController;
    IAToken public aToken;
    IVariableDebtToken public dToken;
    IPriceOracle internal oracle;

    //curve
    ICurve internal constant curve_CRV_YCRV = ICurve(0x453D92C7d4263201C69aACfaf589Ed14202d83a4);
    ICurve internal constant curve_ETH_CRV = ICurve(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511);
    ICurve internal constant curve_ETH_STETH = ICurve(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    ICurve internal constant curve_WETH_STETH = ICurve(0x828b154032950C8ff7CF8085D841723Db2696056);
    ICurve internal constant curve_USDT_WBTC_ETH = ICurve(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46);
    ICurve internal constant curve_DAI_USDC_USDT = ICurve(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);

    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_BPS = 100_00;
    uint256 public swapSlippageBPS; 
    uint256 public maxLossBPS; 

    // stkAave addresses only applicable for Mainnet.
    IStakedAave internal constant stkAave = IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        initializeStrategy(_asset);
    }

    function initializeStrategy(address _asset) public {
        require(address(aToken) == address(0), "already initialized");
        lendingPool = IPool(protocolDataProvider.ADDRESSES_PROVIDER().getPool());
        oracle = IPriceOracle(protocolDataProvider.ADDRESSES_PROVIDER().getPriceOracle());
        aToken = IAToken(lendingPool.getReserveData(asset).aTokenAddress);
        dToken = IVariableDebtToken(lendingPool.getReserveData(CRV).variableDebtTokenAddress);
        require(address(aToken) != address(0), "!aToken");
        require(address(dToken) != address(0), "!dToken");
        rewardsController = aToken.getIncentivesController();

        //approvals:
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);
        ERC20(CRV).safeApprove(address(lendingPool), type(uint256).max);
        ERC20(CRV).safeApprove(address(curve_CRV_YCRV), type(uint256).max);
        ERC20(YCRV).safeApprove(STYCRV, type(uint256).max);
        ERC20(YCRV).safeApprove(address(curve_CRV_YCRV), type(uint256).max);

        // Set uni swapper values
        swapSlippageBPS = 150;
        minAmountToSell = 1e4;
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    }

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should invest up to '_amount' of 'asset'.
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     *
     *call: user deposits --> _invest SANDWICHABLE
     */
    function _invest(uint256 _amount) internal override {
        lendingPool.supply(asset, _amount, address(this), 0);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * Should do any needed parameter checks, '_amount' may be more
     * than is actually available.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * @param _amount, The amount of 'asset' to be freed.
     *
     * call: user withdraws --> _freeFunds SANDWICHABLE
     */
    function _freeFunds(uint256 _amount) internal override {
        // We dont check available liquidity because we need the tx to
        // revert if there is not enough liquidity so we dont improperly
        // pass a loss on to the user withdrawing.
        lendingPool.withdraw(asset, Math.min(_balanceCollateral(), _amount), address(this));
    }

    /**
     * @dev Internal non-view function to harvest all rewards, reinvest
     * and return the accurate amount of funds currently held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * reinvesting etc. to get the most accurate view of current assets.
     *
     * All applicable assets including loose assets should be accounted
     * for in this function.
     *
     * @return _invested A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds.
     *
     *
     * call: keeper harvests & asks for accurate current assets after harvest
     */
    function _totalInvested() internal override returns (uint256 _invested) {
        // Claim and sell any STKAAVE rewards to `asset`.
        //_claimAndSellRewards();

        // deposit any loose funds
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            lendingPool.supply(asset, looseAsset, address(this), 0);
        }

        // LTV checks:
        uint256 currentLTV = _LTV();
        if (currentLTV > LTVborrowLess) {
            _borrowLess(currentLTV);
        } else if (currentLTV < LTVborrowMore) {
            _borrowMore();
        }
        require(_LTV() < LTVborrowLessNOW, "LTV too high!");
        _invested = _balanceAsset()  + _balanceCollateral() + _STYCRVtoAsset(_balanceSTYCRV()) - _CRVtoAsset(_balanceCRVDebt());
    }

    function _borrowMore() internal {
        uint256 debtBalance = _balanceCRVDebt();
        uint256 _LTVtarget = LTVtarget;
        uint256 collateralBalance = _balanceCollateral();
        uint256 CRVToBorrow = collateralBalance * LTVtarget / WAD - debtBalance; //CRV amount to borrow to achieve LTV target
        lendingPool.borrow(CRV, CRVToBorrow, 2, 0, address(this));
        _investCRVtoSTYCRV(CRVToBorrow);
    }

    function _investCRVtoSTYCRV(uint256 _CRVAmount) internal {
        _swapCRVtoYCRV(_CRVAmount);
        IVault(STYCRV).deposit();
    }

    function _borrowLess(uint256 currentLTV) internal {

    }

/*
    function _checkLTV() public view returns () {

    }
*/

    //call: keeper tends
    function _tend(uint256 _totalIdle) internal override {

    }

    //call: keeper tracks to tend if true
    function tendTrigger() external view override returns (bool) {
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL:
    //////////////////////////////////////////////////////////////*/

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceCollateral() internal view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _balanceCRVDebt() internal view returns (uint256) {
        return dToken.balanceOf(address(this));
    }

    function _balanceCRV() internal view returns (uint256) {
        return ERC20(CRV).balanceOf(address(this));
    }

    function _balanceYCRV() internal view returns (uint256) {
        return ERC20(YCRV).balanceOf(address(this));
    }

    function _balanceSTYCRV() internal view returns (uint256) {
        return IVault(STYCRV).balanceOf(address(this));
    }

    function _LTV() internal view returns (uint) {
        uint256 collateralBalance = _balanceCollateral();
        return collateralBalance == 0 ? 0 : _CRVtoAsset(_balanceCRVDebt()) * WAD / collateralBalance;
    }

    function _oracle(uint256 amount, address asset0, address asset1) internal view returns (uint256) {
        address[] memory assets = new address[](2); 
        assets[0] = asset0;
        assets[1] = asset1;
        uint[] memory prices = new uint[](2);
        prices = oracle.getAssetsPrices(assets);
        return amount * prices[0] / prices[1];
    }

    function _CRVtoAsset(uint256 _CRVAmount) internal view returns (uint256) {
        return _oracle(_CRVAmount, CRV, asset);
    }

    function _assetToCRV(uint256 _assetAmount) internal view returns (uint256) {
        return _oracle(_assetAmount, asset, CRV);
    }

    function _STYCRVtoAsset(uint256 _STYCRVAmount) internal view returns (uint256) {
        return _CRVtoAsset(_STYCRVtoCRV(_STYCRVAmount)); 
    }

    function _STYCRVtoCRV(uint256 _STYCRVAmount) internal view returns (uint256) {
        //return _STYCRVAmount * IVault(STYCRV).pricePerShare() / IVault(STYCRV).decimals();
        return _STYCRVAmount * IVault(STYCRV).pricePerShare() / WAD;
    }

    function _swapCRVtoYCRV(uint256 _CRVAmount) internal returns (uint256) {
        curve_CRV_YCRV.exchange(0, 1, _CRVAmount, _CRVAmount * (MAX_BPS - swapSlippageBPS) / MAX_BPS);
    }

    function _swapYCRVtoCRV(uint256 _YCRVAmount) internal returns (uint256) {
        curve_CRV_YCRV.exchange(1, 0, _YCRVAmount, _YCRVAmount * (MAX_BPS - swapSlippageBPS) / MAX_BPS);
    }


    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    function balanceCollateral() external view returns (uint256) {
        return _balanceCollateral();
    }

    function balanceCRVDebt() external view returns (uint256) {
        return _balanceCRVDebt();
    }

    function LTV() external view returns (uint256) {
        return _LTV();
    }

    function balanceCRV() external view returns (uint256) {
        return _balanceCRV();
    }

    function balanceYCRV() external view returns (uint256) {
        return _balanceYCRV();
    }

    function balanceSTYCRV() external view returns (uint256) {
        return _balanceSTYCRV();
    }

    function CRVtoAsset(uint256 _CRVAmount) external view returns (uint256) {
        return _CRVtoAsset(_CRVAmount);
    }

    function assetToCRV(uint256 _assetAmount) external view returns (uint256) {
        return _assetToCRV(_assetAmount);
    }

    function STYCRVtoCRV(uint256 _STYCRVAmount) external view returns (uint256) {
        return _STYCRVtoCRV(_STYCRVAmount);
    }

    function STYCRVtoAsset(uint256 _STYCRVAmount) external view returns (uint256) {
        return _STYCRVtoAsset(_STYCRVAmount);
    }

    function migrateToNewYCRVVault(address _newYCRVVault) external onlyManagement {
        uint256 YCRVBalance = _balanceYCRV();
        if (YCRVBalance > 0) {
            IVault(YCRV).withdraw(YCRVBalance, address(this), maxLossBPS);
        }
        ERC20(CRV).safeApprove(YCRV, 0);
        ERC20(CRV).safeApprove(YCRV, 0);
        YCRV = _newYCRVVault;
        ERC20(CRV).safeApprove(YCRV, type(uint256).max);
        _depositAllYCRVinSTYCRV();
    }

    function _depositAllYCRVinSTYCRV() internal {
        uint256 YCRVbalance = _balanceYCRV();
        if (YCRVbalance > 0) {
            IVault(STYCRV).deposit();
        }
    }

    // Max slippage to accept when swapping:
    function setSwapSlippageBPS(uint256 _swapSlippageBPS) external onlyManagement {
        require(_swapSlippageBPS <= MAX_BPS);
        swapSlippageBPS = _swapSlippageBPS;
    }

    // Max Loss to accept when withdrawing from STYCRV:
    function setMaxLossBPS(uint256 _maxLossBPS) external onlyManagement {
        require(_maxLossBPS <= MAX_BPS);
        maxLossBPS = _maxLossBPS;
    }

    function emergencyWithdraw(uint256 _amount) external onlyManagement {
        lendingPool.withdraw(asset, _amount, address(this));
    }

    function cloneStrategy(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external returns (address newStrategy) {
        // Use the cloning logic held withen the Base library.
        newStrategy = TokenizedStrategy.clone(
            _asset,
            _name,
            _management,
            _performanceFeeRecipient,
            _keeper
        );
        // Neeed to cast address to payable since there is a fallback function.
        Strategy(payable(newStrategy)).initializeStrategy(_asset);
    }











    /*//////////////////////////////////////////////////////////////
               AAVE TOKEN & STKAAVE TOKEN FUNCTIONS:
    //////////////////////////////////////////////////////////////*/

    
    function _claimAndSellRewards() internal {
        // Need to redeem any aave from StkAave if applicable before
        // claiming rewards and staring cool down over
        _redeemAave();

        //claim all rewards
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList, ) = rewardsController
            .claimAllRewardsToSelf(assets);

        //swap as much as possible back to want
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == address(stkAave)) {
                _harvestStkAave();
            } else if (token == asset) {
                continue;
            } else {
                _swapFrom(
                    token,
                    asset,
                    ERC20(token).balanceOf(address(this)),
                    0
                );
            }
        }
    }

    function _redeemAave() internal {
        if (!_checkCooldown()) {
            return;
        }

        uint256 stkAaveBalance = ERC20(address(stkAave)).balanceOf(
            address(this)
        );

        if (stkAaveBalance > 0) {
            stkAave.redeem(address(this), stkAaveBalance);
        }

        // sell AAVE for want
        _swapFrom(AAVE, asset, ERC20(AAVE).balanceOf(address(this)), 0);
    }

    function _checkCooldown() internal view returns (bool) {
        if (block.chainid != 1) {
            return false;
        }

        uint256 cooldownStartTimestamp = IStakedAave(stkAave).stakersCooldowns(
            address(this)
        );

        if (cooldownStartTimestamp == 0) return false;

        uint256 COOLDOWN_SECONDS = IStakedAave(stkAave).COOLDOWN_SECONDS();
        uint256 UNSTAKE_WINDOW = IStakedAave(stkAave).UNSTAKE_WINDOW();
        if (block.timestamp >= cooldownStartTimestamp + COOLDOWN_SECONDS) {
            return
                block.timestamp - (cooldownStartTimestamp + COOLDOWN_SECONDS) <=
                UNSTAKE_WINDOW;
        } else {
            return false;
        }
    }

    function _harvestStkAave() internal {
        // request start of cooldown period
        if (ERC20(address(stkAave)).balanceOf(address(this)) > 0) {
            stkAave.cooldown();
        }
    }

    function manualRedeemAave() external onlyKeepers {
        _redeemAave();
    }
    
}
