// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import {BaseHealthCheck} from "@periphery/HealthCheck/BaseHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBalancer, IBalancerPool} from "./interfaces/Balancer/IBalancer.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "./interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IPriceOracle} from "./interfaces/Aave/V3/IPriceOracle.sol";
import {IAToken} from "./interfaces/Aave/V3/IAToken.sol";
import {IVariableDebtToken} from "./interfaces/Aave/V3/IVariableDebtToken.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

/// @title yearn-v3-leveraged-LST-POLYGON-STMATIC
/// @author mil0x
/// @notice yearn-v3 Strategy that uses MATIC to leverage its Liquid Staking Token (LST) stMATIC on AAVE for leveraged yield.
contract Strategy is BaseHealthCheck, UniswapV3Swapper {
    using SafeERC20 for ERC20;
    enum Action {WIND, UNWIND}
    enum Swapper {UNIV3, BALANCER}

    //Desired Loan-to-Value
    uint256 public targetLoanToValue;
    uint256 public emergencyUnwindLoanToValue;
    uint256 public unwindLoanToValue;
    uint256 public windLoanToValue;

    uint256 public depositLimit = type(uint256).max; //Manual limit of total deposits
    uint256 public maxBorrowRate;

    // Parameters
    Swapper public swapper;
    address public swapPool;
    bool public useFlashloan; //use a flashloan to manage CDP (true) or use loops (false)
    address public flashloanProvider = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 public expectedFlashloanFee;
    uint256 public maxLoops; //maximum number of loops to use if flashloans are deactivated

    uint256 public maxSingleTrade; //maximum amount that should be swapped by the keeper in one go
    uint256 public maxSingleWithdraw; //maximum amount that should be withdrawn in one go

    uint256 public swapSlippage; //actual slippage for a trade
    uint256 public bufferSlippage; //pessimistic buffer to the totalAssets to simulate having to realize the LST to asset
    uint256 public depositTrigger; //amount in asset that will trigger a tend if idle.  
    uint256 public minDepositInterval; //minimum time between deposits to wait.
    uint256 public lastDeposit; //timestamp of the last deployment of funds.
    bool public open = true; //bool if the strategy is open for any depositors.
    mapping(address => bool) public allowed; //mapping of addresses allowed to deposit.

    uint256 public maxTendBasefee; //max amount the base fee can be for a tend to happen

    bool internal flashloanActive; //security variable to use when calling flashloans

    //Immutables & Constants:
    uint256 internal immutable ASSET_DUST; //negligible amount of asset, something like 0.1$ to know when to stop loops.
    address public immutable LST;
    uint8 internal immutable EMODE;
    IPool private immutable lendingPool;
    IProtocolDataProvider private immutable protocolDataProvider;
    IPriceOracle private immutable priceOracle;
    IAToken private immutable aToken;
    IVariableDebtToken private immutable debtToken;
    address internal immutable GOV;

    address internal constant BALANCER = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant COLLATERAL_DUST = 10;
    uint256 internal constant DEBT_DUST = 5;
    uint16 private constant REF = 0;

    constructor(address _asset, uint256 _ASSET_DUST, address _LST, address _protocolDataProvider, Swapper _swapper, address _swapPool, bool _useFlashloan, address _GOV, string memory _name) BaseHealthCheck(_asset, _name) {
        LST = _LST;
        swapper = _swapper;
        swapPool = _swapPool;
        if (swapper == Swapper.BALANCER) {
            require(_swapPool != address(0), "swapPool==0");
        }
        useFlashloan = _useFlashloan;
        maxLoops = 30;
        GOV = _GOV;
    
        emergencyUnwindLoanToValue = (90_00 * WAD) / 100_00;
        unwindLoanToValue = (81_00 * WAD) / 100_00;
        targetLoanToValue = (80_00 * WAD) / 100_00;
        windLoanToValue = (75_00 * WAD) / 100_00;
        ASSET_DUST = _ASSET_DUST; //negligible amount of asset, something like 0.1$ to know when to stop loops

        protocolDataProvider = IProtocolDataProvider(_protocolDataProvider);
        lendingPool = IPool(protocolDataProvider.ADDRESSES_PROVIDER().getPool());
        priceOracle = IPriceOracle(protocolDataProvider.ADDRESSES_PROVIDER().getPriceOracle());

        // 4.4% APR maximum acceptable variable borrow rate from lender:
        maxBorrowRate = 44 * 1e24;

        depositTrigger = 10 * 1e18; //minimum amoun that should be leveraged up
        maxSingleTrade = 10_000 * 1e18; //maximum amount that should be swapped by the keeper in one go
        maxSingleWithdraw = 50_000 * 1e18; //maximum amount that should be withdrawn in one go
        swapSlippage = 20_00; //actual slippage for a trade
        bufferSlippage = 0; //pessimistic correction to the totalAssets to simulate having to realize the LST to asset and thus virtually create a buffer for swapping

        maxTendBasefee = 100e9; //default max tend fee to 100 gwei
        minDepositInterval = 60 * 60 * 6; //default min deposit interval to 6 hours

        // Set uni swapper values
        minAmountToSell = 1;
        base = _asset;
        _setUniFees(_asset, LST, 100); //use setUniFees external function to overwrite this default value
        _setUniFees(LST, _asset, 100);

        // Set aave tokens
        (address _aToken, , ) = protocolDataProvider.getReserveTokensAddresses(LST);
        ( , , address _debtToken) = protocolDataProvider.getReserveTokensAddresses(address(asset));
        aToken = IAToken(_aToken);
        debtToken = IVariableDebtToken(_debtToken);

        // Enable EMode for asset:
        EMODE = uint8(protocolDataProvider.getReserveEModeCategory(LST));
        lendingPool.setUserEMode(EMODE);

        //approvals:
        ERC20(_asset).safeApprove(BALANCER, type(uint256).max);
        ERC20(LST).safeApprove(BALANCER, type(uint256).max);
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);
        ERC20(LST).safeApprove(address(lendingPool), type(uint256).max);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        _repayDebt(_amount);
    }

    function _tend(uint256 /*_totalIdle*/) internal override {
        _manageCDP();
    }

    function _tendTrigger() internal view override returns (bool) {
        uint256 _currentLoanToValue = currentLoanToValue();
        // Unwind if we need to repay debt and are outside the tolerance bands, we do it regardless of the call cost
        if (_currentLoanToValue >= emergencyUnwindLoanToValue) {
            return true;
        }

        if (block.basefee >= maxTendBasefee) {
            return false;
        }

        if (_currentLoanToValue >= unwindLoanToValue) {
            return true;
        }

        if (TokenizedStrategy.isShutdown()) {
            return false;
        }
        
        if (_balanceOfAsset() >= depositTrigger && _maxDepositableCollateral() >= depositTrigger && block.timestamp - lastDeposit > minDepositInterval) {
            return true;
        }

        if (_currentLoanToValue <= windLoanToValue && balanceOfCollateral() > COLLATERAL_DUST) {
            return true;
        }

        return false;
    }

    /*//////////////////////////////////////////////////////////////
                LEVERAGE
    //////////////////////////////////////////////////////////////*/

    function _manageCDP() internal {
        console.log("_manageCDP");
        uint256 looseLST = balanceOfLST();
        uint256 maximumAmountToDeposit = _maxDepositableCollateral();
        looseLST = Math.min(looseLST, maximumAmountToDeposit);
        if (looseLST > 0) {
            lendingPool.deposit(LST, looseLST, address(this), REF);
        }
        uint256 _currentLoanToValue = currentLoanToValue();
        uint256 _targetLoanToValue = targetLoanToValue;
        if (_currentLoanToValue >= unwindLoanToValue) { //check if we need to unwind
            unwind(0);
        } else if (!TokenizedStrategy.isShutdown()) {
            (,,,,,,uint256 currentVariableBorrowRate,,,,,) = protocolDataProvider.getReserveData(address(asset)); //1% borrowing APR = 1e25. Percentage value in wad (1e27)
            if (currentVariableBorrowRate <= maxBorrowRate) {
                uint256 assetBalance = balanceOfAsset();
                if (assetBalance > depositTrigger || _currentLoanToValue < windLoanToValue) { //check if we need to wind OR if there is enough loose asset to wind
                    console.log("_manageCDP: wind");
                    console.log("assetBalance", assetBalance);
                    console.log("_targetLoanToValue", _targetLoanToValue);
                    wind(assetBalance, _targetLoanToValue);
                    console.log("BALANCE OF ASSET: ", balanceOfAsset());
                }
            }
        }
        console.log("currentLoanToValue()", currentLoanToValue());
        
        //repay debt if there is any loose asset:
        _repayDebt(balanceOfAsset());

        //Check safety of the CDP after all actions:
        if (balanceOfDebt() > DEBT_DUST) {
            require(currentLoanToValue() < emergencyUnwindLoanToValue, "unsafe CDP (_manageCDP)");
        }
    }

    function _maxDepositableCollateral() internal view returns (uint256) {
        (, uint256 supplyCap) = protocolDataProvider.getReserveCaps(LST);
        uint256 maximumAmount = supplyCap * WAD;
        uint256 currentAmount = IAToken(aToken).totalSupply();
        if (currentAmount + ASSET_DUST >= maximumAmount) {
            return 0;
        } else {
            return maximumAmount - currentAmount - ASSET_DUST;
        }
    }

    function _maxUnlockableCollateral() internal view returns (uint256) {
        uint256 collateralBalance = balanceOfCollateral();
        console.log("_MAXUNLOCKABLECOLLATERAL: collateralBalance: ", collateralBalance);
        uint256 debtBalance = balanceOfDebt() * WAD / getAssetPerLST();
        console.log("_MAXUNLOCKABLECOLLATERAL: debtBalance: ", debtBalance);
        if (debtBalance == 0) {
            return collateralBalance;
        }
        uint256 LT = uint256(lendingPool.getEModeCategoryData(EMODE).liquidationThreshold);
        LT = LT * 1e14; //liquidation threshold
        console.log("_MAXUNLOCKABLECOLLATERAL: debtBalance * WAD / (LT - 1e15): ", debtBalance * WAD / (LT - 1e15));
        console.log("return: ", collateralBalance - debtBalance * WAD / (LT - 1e15));
        return collateralBalance - debtBalance * WAD / (LT - 1e15); //unlock collateral up to 0.1% less than liquidation threshold
    }

    function wind(
        uint256 _assetAmountInitial,
        uint256 _targetLoanToValue
    ) public {
        uint256 assetPerLST = getAssetPerLST();
        uint256 currentDebt = balanceOfDebt();
        if (!useFlashloan) { //No Flashloan:
            uint256 _maxLoops = maxLoops;
            uint256 toSwap = _assetAmountInitial;
            uint256 maxDeposit = _maxDepositableCollateral();
            uint256 collateralBalance = balanceOfCollateral();
            for (uint256 i = 0; i < _maxLoops; ++i) {
                uint256 LSTAmountToLock = _swapAssetToLST(toSwap);
                console.log("LSTAmountToLock", LSTAmountToLock);
                if (LSTAmountToLock > maxDeposit) {
                    _depositCollateral(maxDeposit);
                    return;
                }
                _depositCollateral(LSTAmountToLock);
                collateralBalance += LSTAmountToLock;
                maxDeposit -= LSTAmountToLock;
                uint256 targetDebt = collateralBalance * assetPerLST * _targetLoanToValue / WAD / WAD;
                if (i + 1 < _maxLoops && targetDebt > currentDebt + ASSET_DUST) {
                    toSwap = targetDebt - currentDebt;
                    _borrowAsset(toSwap);
                    currentDebt += toSwap;
                } else {
                    console.log("DONE: ", i);
                    return;
                }
            }
        } else {
            uint256 collateralBalance = balanceOfCollateral() * assetPerLST / WAD;
            console.log("collateralBalance", collateralBalance);
            uint256 totalAssets = _assetAmountInitial + collateralBalance;
            console.log("totalAssets", totalAssets);
            uint256 targetCollateral = ( _assetAmountInitial + collateralBalance * (WAD - currentLoanToValue()) / WAD ) * WAD / (WAD - _targetLoanToValue);
            console.log("targetCollateral", targetCollateral);
            console.log("_maxDepositableCollateral()", _maxDepositableCollateral());
            targetCollateral = Math.min(targetCollateral, _maxDepositableCollateral() * assetPerLST / WAD + collateralBalance);
            console.log("targetCollateral", targetCollateral);
            if (targetCollateral < COLLATERAL_DUST) {
                return;
            }
            console.log("currentDebt", currentDebt);
            uint256 flashloanAmount = targetCollateral * _targetLoanToValue / WAD - currentDebt;
            console.log("flashloanAmount", flashloanAmount);
            //Retrieve upper max limit of flashloan:
            uint256 flashloanMaximum = asset.balanceOf(address(flashloanProvider));
            console.log("flashloanMaximum", flashloanMaximum);
            //Cap flashloan only up to maximum allowed:
            flashloanAmount = Math.min(flashloanAmount, flashloanMaximum);
            console.log("flashloanAmount", flashloanAmount);
            bytes memory data = abi.encode(Action.WIND, _assetAmountInitial); 
            _initFlashLoan(data, flashloanAmount);
        }
        console.log("FINAL COLLATERAL: ", balanceOfCollateral() * assetPerLST / WAD);
        console.log("BALANCEOFASSET", balanceOfAsset());
        console.log("BALANCEOFLST", balanceOfLST());
    }
    
    function unwind(
        uint256 _percentageOfSharesToRedeem
    ) public {
        if (balanceOfCollateral() < COLLATERAL_DUST){
            return;
        }
        uint256 _currentLoanToValue = currentLoanToValue();
        uint256 _targetLoanToValue = targetLoanToValue;
        uint256 assetPerLST = getAssetPerLST();
        uint256 currentCollateral = balanceOfCollateral();
        uint256 targetCollateral;
        uint256 currentDebt = balanceOfDebt();
        console.log("currentDebt", currentDebt);
        uint256 targetDebt;
        if (_percentageOfSharesToRedeem == 0) {
            targetCollateral = ( currentCollateral * (WAD - _currentLoanToValue) / WAD ) * WAD / (WAD - _targetLoanToValue);
            targetDebt = targetCollateral * assetPerLST * _targetLoanToValue / WAD / WAD;
        } else {
            _percentageOfSharesToRedeem = Math.min(WAD, _percentageOfSharesToRedeem);
            targetCollateral = currentCollateral * (WAD - _percentageOfSharesToRedeem) / WAD;
            console.log("targetCollateral", targetCollateral);
            targetDebt = currentDebt * (WAD - _percentageOfSharesToRedeem) / WAD;
            console.log("targetDebt", targetDebt);
        }
        console.log("targetCollateral", targetCollateral);
        console.log("targetDebt", targetDebt);
        uint256 collateralToSell = currentCollateral - targetCollateral;
        console.log("BEFORE LOOP: collateralToSell", collateralToSell);

        if (!useFlashloan) { //No Flashloan:
            uint256 _maxLoops = maxLoops;
            console.log("_maxLoops", _maxLoops);
            
            uint256 toSwap;
            uint256 debtLeftToRepay = currentDebt - targetDebt;
            console.log("START: debtLeftToRepay", debtLeftToRepay);
            
            for (uint256 i = 0; i < _maxLoops; ++i) {
                console.log("i ", i);
                console.log("DEBT LEFT TO REPAY: ", debtLeftToRepay);
                uint256 maxUnlockableCollateral = _maxUnlockableCollateral();
                console.log("collateralToSell > maxUnlockableCollateral", collateralToSell > maxUnlockableCollateral);
                if (maxUnlockableCollateral == 0) {
                    return;
                }
                if (collateralToSell > maxUnlockableCollateral) {
                    console.log("maxUnlockableCollateral", maxUnlockableCollateral);
                    _withdrawCollateral(maxUnlockableCollateral);
                    toSwap = maxUnlockableCollateral;
                    collateralToSell -= maxUnlockableCollateral;
                    console.log("collateralToSell", collateralToSell);
                } else {
                    console.log("else");
                    _withdrawCollateral(collateralToSell);
                    toSwap = collateralToSell;
                    collateralToSell = 0;
                    console.log("collateralToSell", collateralToSell);
                }
                uint256 toRepay = _swapLSTtoAsset(toSwap);
                console.log("toRepay", toRepay);
                //check if we need to stop repayingDebt for user withdraw
                console.log("debtLeftToRepay", debtLeftToRepay);
                if (toRepay > debtLeftToRepay) {
                    _repayDebt(debtLeftToRepay);
                    debtLeftToRepay = 0;
                } else if (toRepay > 0) {
                    _repayDebt(toRepay);
                    debtLeftToRepay -= toRepay;
                }
                console.log("debtLeftToRepay", debtLeftToRepay);
                if (collateralToSell == 0 || i + 2 > _maxLoops) {
                    return;
                }
            }
        } else { //FLASHLOAN:
            uint256 flashloanAmount = currentDebt - targetDebt;
            console.log("flashloanAmount", flashloanAmount);
            //Retrieve for upper max limit of flashloan:
            uint256 flashloanMaximum = asset.balanceOf(address(flashloanProvider));
            //Cap flashloan only up to maximum allowed:
            if (flashloanMaximum < flashloanAmount) {
                flashloanAmount = flashloanMaximum;
                collateralToSell = Math.min(currentCollateral - (currentDebt - flashloanAmount) * WAD * WAD / assetPerLST / _targetLoanToValue, collateralToSell);
            }
            console.log("flashloanAmount", flashloanAmount);
            console.log("collateralToSell", collateralToSell);
            bytes memory data = abi.encode(Action.UNWIND, collateralToSell);
            //Always flashloan entire debt to pay off entire debt:
            _initFlashLoan(data, flashloanAmount);
        }
    }

    function _initFlashLoan(bytes memory data, uint256 amount)
        public
    {
        address[] memory tokens = new address[](1);
        tokens[0] = address(asset);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        flashloanActive = true;
        IBalancer(flashloanProvider).flashLoan(address(this), tokens, amounts, data);
    }

    // ----------------- FLASHLOAN CALLBACK -----------------
    //Flashloan Callback:
    function receiveFlashLoan(
        ERC20[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata fees,
        bytes calldata data
    ) external {
        require(msg.sender == flashloanProvider);
        require(flashloanActive == true);
        flashloanActive = false;
        uint256 fee = fees[0];
        require(fee <= expectedFlashloanFee, "fee > expectedFlashloanFee");
        (Action action, uint256 _assetAmountInitialOrCollateralToSell) = abi.decode(data, (Action, uint256));
        uint256 amount = amounts[0];
        if (action == Action.WIND) {
            _wind(amount, amount + fee, _assetAmountInitialOrCollateralToSell);
        } else if (action == Action.UNWIND) {
            _unwind(amount, amount + fee, _assetAmountInitialOrCollateralToSell);
        }
    }

    function _wind(uint256 flashloanAmount, uint256 flashloanRepayAmount, uint256 assetAmountInitial) internal {
        //repayAmount includes any fees
        console.log("assetAmountInitial", assetAmountInitial);
        console.log("flashloanAmount", flashloanAmount);
        uint256 LSTAmountToLock = _swapAssetToLST(assetAmountInitial + flashloanAmount);
        console.log("LSTAmountToLock", LSTAmountToLock);
        //Lock collateral and borrow asset to repay flashloan
        _depositCollateral(LSTAmountToLock);
        _borrowAsset(flashloanRepayAmount);
        
        //repay flashloan:
        asset.transfer(address(flashloanProvider), flashloanRepayAmount);
    }

    function _unwind(uint256 flashloanAmount, uint256 flashloanRepayAmount, uint256 collateralToSell) internal {
        console.log("balanceOfDebt()", balanceOfDebt());
        _repayDebt(flashloanAmount);
        console.log("balanceOfDebt()", balanceOfDebt());
        console.log("collateralToSell", collateralToSell);
        _withdrawCollateral(collateralToSell);
        //Desired collateral amount unlocked --> swap to asset
        console.log("balanceOfAsset()", balanceOfAsset());
        console.log("balanceOfLST()", balanceOfLST());
        _swapLSTtoAsset(collateralToSell);
        console.log("balanceOfAsset()", balanceOfAsset());
        console.log("balanceOfLST()", balanceOfLST());
        //----> Asset amount requested now in wallet

        uint256 assetBalance = balanceOfAsset();
        require(assetBalance >= flashloanRepayAmount, "not enough asset to repay flashloan");
        
        //repay flashloan:
        asset.transfer(address(flashloanProvider), flashloanRepayAmount);
        console.log("balanceOfAsset", balanceOfAsset());
    }

    function _borrowAsset(uint256 amount) internal {
        if (amount == 0) return;
        lendingPool.setUserUseReserveAsCollateral(LST, true);
        lendingPool.setUserEMode(EMODE);
        lendingPool.borrow(address(asset), amount, 2, REF, address(this));
    }

    function _swapAssetToLST(uint256 _amount) internal returns (uint256) {
        _amount = Math.min(_amount, balanceOfAsset());
        if (_amount == 0) {
            return 0;
        }
        console.log("swapBalancer before reentrancy");
        console.log("_amount * WAD * (MAX_BPS - swapSlippage) / getAssetPerLST() / MAX_BPS", _amount * WAD * (MAX_BPS - swapSlippage) / getAssetPerLST() / MAX_BPS);
        if (swapper == Swapper.UNIV3) {
            return _swapFrom(address(asset), LST, _amount, _amount * WAD * (MAX_BPS - swapSlippage) / getAssetPerLST() / MAX_BPS); //minAmountOut in LST, account for swapping slippage
        } else {
            return swapBalancer(address(asset), LST, _amount, _amount * WAD * (MAX_BPS - swapSlippage) / getAssetPerLST() / MAX_BPS); 
        }
    }

    function _swapLSTtoAsset(uint256 _amount) internal returns (uint256) {
        _amount = Math.min(_amount, balanceOfLST());
        if (_amount == 0) {
            return 0;
        }
        console.log("swapBalancer before reentrancy");
        console.log("_amount * getAssetPerLST() * (MAX_BPS - swapSlippage) / WAD / MAX_BPS", _amount * getAssetPerLST() * (MAX_BPS - swapSlippage) / WAD / MAX_BPS);
        if (swapper == Swapper.UNIV3) {
            return _swapFrom(LST, address(asset), _amount, _amount * getAssetPerLST() * (MAX_BPS - swapSlippage) / WAD / MAX_BPS); //minAmountOut in asset, account for swapping slippage
        } else {
            return swapBalancer(LST, address(asset), _amount, _amount * getAssetPerLST() * (MAX_BPS - swapSlippage) / WAD / MAX_BPS); //minAmountOut in asset, account for swapping slippage
        }
    }

    // ----------------- PUBLIC BALANCES AND CALCS -----------------
    /// @notice Returns the amount of asset the strategy holds.
    function balanceOfAsset() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Returns the amount of staked asset in liquid staking token (LST) the strategy holds.
    function balanceOfLST() public view returns (uint256) {
        return ERC20(LST).balanceOf(address(this));
    }

    function getAssetPerLST() public view returns (uint256){
        return WAD * _getTokenPrice(address(asset)) / _getTokenPrice(address(LST));
    }

    function balanceOfCollateral() public view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function balanceOfDebt() public view returns (uint256) {
        return debtToken.balanceOf(address(this));
    }

    // Current Loan-to-Value of the CDP
    function currentLoanToValue() public view returns (uint256) {
        uint256 totalCollateral = balanceOfCollateral();
        if (totalCollateral < COLLATERAL_DUST) {
            return 0;
        }
        return balanceOfDebt() * WAD * WAD / (totalCollateral * getAssetPerLST());
    }

    // ----------------- AAVE INTERNAL CALCS -----------------

    function _depositCollateral(uint256 _amount) internal {
        _amount = Math.min(balanceOfLST(), _amount);
        if (_amount < COLLATERAL_DUST) return;
        lendingPool.deposit(LST, _amount, address(this), REF);
    }

    function _withdrawCollateral(uint256 _amount) internal {
        _amount = Math.min(balanceOfCollateral(), _amount);
        if (_amount < COLLATERAL_DUST) return;
        lendingPool.withdraw(LST, _amount, address(this));
    }

    function _repayDebt(uint256 amount) internal {
        amount = Math.min(amount, balanceOfDebt());
        if (amount == 0) return;
        lendingPool.repay(address(asset), amount, 2, address(this));
    }

    function _getTokenPrice(address _token) internal view returns (uint256){
        return WAD * WAD / priceOracle.getAssetPrice(_token);
    }

    function swapBalancer(address _tokenIn, address _tokenOut, uint256 _amount, uint256 _minAmountOut) internal returns (uint256) {
        IBalancer.SingleSwap memory singleSwap;
        singleSwap.poolId = IBalancerPool(swapPool).getPoolId();
        singleSwap.kind = 0;
        singleSwap.assetIn = _tokenIn;
        singleSwap.assetOut = _tokenOut;
        singleSwap.amount = _amount;
        IBalancer.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = true;
        funds.recipient = payable(this);
        funds.toInternalBalance = false;
        return IBalancer(BALANCER).swap(singleSwap, funds, _minAmountOut, block.timestamp);
    }

    function availableDepositLimit(address _owner) public view override returns (uint256) {
        // If the owner is whitelisted or the strategy is open.
        if (open || allowed[_owner]) {
            if (depositLimit == type(uint256).max) {
                return type(uint256).max;
            } else {
                uint256 totalAssets = TokenizedStrategy.totalAssets();
                if (totalAssets < depositLimit) {
                    return depositLimit - totalAssets;
                } else {
                    return 0;
                }
            }
        } else {
            return 0;
        }
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return TokenizedStrategy.totalIdle() + maxSingleWithdraw;
    }
    
    function _freeFunds(uint256 _assetAmount) internal override {
        console.log("FREE FUNDS: _assetAmount: ", _assetAmount);
        console.log("TokenizedStrategy.totalDebt()", TokenizedStrategy.totalDebt());
        uint256 percentageOfSharesToRedeem = _assetAmount * WAD / TokenizedStrategy.totalDebt();
        console.log("percentageOfSharesToRedeem", percentageOfSharesToRedeem);
        if (percentageOfSharesToRedeem > 0) {
            unwind(percentageOfSharesToRedeem);
        }
        uint256 assetBalance = balanceOfAsset();
        console.log("assetBalance", assetBalance);
        console.log("_assetAmount", _assetAmount);
        console.log("assetBalance > _assetAmount", assetBalance > _assetAmount);
        if (assetBalance > _assetAmount) {
            console.log("assetBalance > _assetAmount", assetBalance - _assetAmount);
            _repayDebt(assetBalance - _assetAmount);
        }

        if (balanceOfDebt() > DEBT_DUST) {
            require(currentLoanToValue() < emergencyUnwindLoanToValue, "unsafe CDP (_freeFunds)");
        }
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // invest any loose asset
        if (!TokenizedStrategy.isShutdown()) {
            _manageCDP();
        }
        // new total assets of the strategy, pessimistically account for LST at a value as if it had been swapped back to asset with the swap fee and a virtual swap slippage
        console.log("before _totalAssets");
        uint256 collateralBalance = _balanceOfAsset() + (_balanceOfLST() + balanceOfCollateral()) * getAssetPerLST() * (MAX_BPS - bufferSlippage) / WAD / MAX_BPS;
        uint256 debtBalance = balanceOfDebt();
        if (debtBalance >= collateralBalance) {
            _totalAssets = 0;
        } else {
            _totalAssets = collateralBalance - debtBalance;
        }
        console.log("_totalAssets", _totalAssets);
    }

    function _balanceOfAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceOfLST() internal view returns (uint256){
        return ERC20(LST).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function setLoanToValueTargets(uint256 _targetLoanToValue, uint256 _emergencyUnwindLoanToValue, uint256 _unwindLoanToValue, uint256 _windLoanToValue) external onlyManagement {
        uint256 LT = uint256(lendingPool.getEModeCategoryData(EMODE).liquidationThreshold);
        LT = LT * 1e14; //liquidation threshold
        require(LT >= _emergencyUnwindLoanToValue);
        require(_emergencyUnwindLoanToValue >= _unwindLoanToValue);
        require(_unwindLoanToValue >= _targetLoanToValue);
        require(_targetLoanToValue >= windLoanToValue);
        targetLoanToValue = _targetLoanToValue;
        emergencyUnwindLoanToValue = _emergencyUnwindLoanToValue;
        unwindLoanToValue = _unwindLoanToValue;
        windLoanToValue = _windLoanToValue;
    }

    /// @notice Set the maximum amount of asset that can be moved by keepers in a single transaction. This is to avoid unnecessarily large slippages when harvesting.
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyManagement {
        maxSingleTrade = _maxSingleTrade;
    }

    /// @notice Set the maximum amount of asset that can be withdrawn in a single transaction. This is to avoid unnecessarily large slippages and incentivizes staggered withdrawals.
    function setMaxSingleWithdraw(uint256 _maxSingleWithdraw) external onlyManagement {
        maxSingleWithdraw = _maxSingleWithdraw;
    }

    /// @notice Set the limit that can be deposited into the strategy.
    function setDepositLimit(uint256 _depositLimit) external onlyManagement {
        depositLimit = _depositLimit;
    }

    /// @notice Set the amount in asset that should trigger a tend if idle.
    function setDepositTrigger(uint256 _depositTrigger) external onlyManagement {
        depositTrigger = _depositTrigger;
    }

    /// @notice Set the minimum deposit wait time.
    function setDepositInterval(uint256 _newDepositInterval) external onlyManagement {
        // Cannot set to 0.
        require(_newDepositInterval > 0, "interval too low");
        minDepositInterval = _newDepositInterval;
    }

    /// @notice Set the maximum variable borrow rate for asset that we still wind up for.
    function setMaxBorrowRate (uint256 _maxBorrowRate) external onlyManagement {
        maxBorrowRate = _maxBorrowRate;
    }

    /// @notice Change if anyone can deposit in or only white listed addresses
    function setOpen(bool _open) external onlyManagement {
        open = _open;
    }

    /// @notice Set or update an addresses whitelist status.
    function setAllowed(address _address, bool _allowed) external onlyManagement {
        allowed[_address] = _allowed;
    }

    /// @notice Set the max base fee for tending to occur at.
    function setMaxTendBasefee(uint256 _maxTendBasefee) external onlyManagement {
        maxTendBasefee = _maxTendBasefee;
    }

    /// @notice Set the expected flashloan fee, usually assumed to be zero, so we do not get a surprise flashloan fee.
    function setExpectedFlashloanFee(uint256 _expectedFlashloanFee) external onlyManagement {
        expectedFlashloanFee = _expectedFlashloanFee;
    }

    /// @notice Set the buffer slippage in basis points (BPS) to pessimistically correct the totalAssets to reflect having to eventually swap LST back to asset and thus create a buffer for swaps.
    function setBufferSlippage(uint256 _bufferSlippage) external onlyManagement {
        require(_bufferSlippage <= MAX_BPS);
        bufferSlippage = _bufferSlippage;
    }

    /// @notice Set the Swapper through which all swaps are routed.
    function setSwapper(Swapper _swapper, address _swapPool) external onlyManagement {
        if (_swapper == Swapper.BALANCER) {
            require(_swapPool != address(0));
        }
        swapper = _swapper;
        if (swapPool != address(0)) {
            swapPool = _swapPool;
        }
    }

    /// @notice Set the maximum slippage in basis points (BPS) to accept when swapping asset <-> staked asset in liquid staking token (LST).
    function setSwapSlippage(uint256 _swapSlippage) external onlyManagement {
        require(_swapSlippage <= MAX_BPS);
        swapSlippage = _swapSlippage;
    }

    /// @notice Set the UniswapV3 fee pools to choose for swapping between asset, borrowToken (BT) or base (intermediate token for better swaps).
    function setUniFees(address _token0, address _token1, uint24 _fee) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    /// @notice Set the UniswapV3 minimum amount to swap i.e. dust.
    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /// @notice Set the wind and unwind functions to use Flashloans (true) or loops (false). 
    function setUseFlashloan(bool _useFlashloan) external onlyManagement {
        useFlashloan = _useFlashloan;
    }

    /// @notice Set the maximum number of loops to use if useFlashloan is deactivated. 
    function setMaxLoops(uint256 _maxLoops) external onlyManagement {
        maxLoops = _maxLoops;
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }

    /// @notice Set the flashloanProvider address in case balancer does not work anymore. Only callable by governance.
    function setFlashloanProvider(address _flashloanProvider) external onlyGovernance {
        require(_flashloanProvider != address(0));
        flashloanProvider = _flashloanProvider;
    }

    /// @notice Manage the CDP manually in an emergency situation. Only callable by governance.
    /// @param _function Choose the function: 0 == deposit, 1 == repay, 2 == withdraw.
    /// @param _token Choose the token to use with the selected function.
    /// @param _amount Choose the amount of token to use with the selected function.
    function emergencyManageCDP(uint256 _function, address _token, uint256 _amount) external onlyGovernance {
        if (_function == 0) {
            lendingPool.deposit(_token, _amount, address(this), REF);
        } else if (_function == 1) {
            lendingPool.repay(_token, _amount, 2, address(this));
        } else if (_function == 2) {
            lendingPool.withdraw(_token, _amount, address(this));
        } else {
            revert("wrong _function selector");
        }
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance. Only callable by governance.
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset));
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY:
    //////////////////////////////////////////////////////////////*/

    // Emergency adjust LTV
    function _emergencyWithdraw(uint256 _percentage) internal override {
        unwind(_percentage);
    }
}
