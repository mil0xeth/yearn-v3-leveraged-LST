// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/maker/IMaker.sol";

// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract Strategy is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    PotLike  public pot = PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    DaiJoinLike internal constant daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);
    //VatLike  public vat = VatLike(0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B);
    //GemLike  public daiToken = GemLike(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        initializeStrategy(_asset);
    }

    function initializeStrategy(address _asset) public {
        //require(address(aToken) == address(0), "already initialized");

        //approvals:
        ERC20(_asset).safeApprove(address(daiJoin), type(uint256).max);

        VatLike vat = VatLike(pot.vat());
        vat.hope(address(daiJoin));
        vat.hope(address(pot));

        // Set uni swapper values
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
        _join(address(this), _amount);
    }

    function _join(address dst, uint256 wad) internal {
        uint256 chi = (block.timestamp > pot.rho()) ? pot.drip() : pot.chi();
        uint256 pie = _rdiv(wad, chi);
        daiJoin.join(address(this), wad);
        pot.join(pie);
    }

    function _rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = x * y / RAY;
    }

    function _rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = x * RAY / y;
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
        _exit(address(this), _amount);
    }

    function _exit(address dst, uint256 wad) internal {
        uint256 chi = (block.timestamp > pot.rho()) ? pot.drip() : pot.chi();
        uint256 pie = _rdivup(wad, chi);
        pie = Math.min(pot.pie(address(this)), pie);
        pot.exit(pie);
        uint256 amt = _rmul(chi, pie);
        daiJoin.exit(dst, amt);
    }
    
    function _rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds up
        z = ( x * RAY + (y - 1) ) / y;
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
        // deposit any loose funds
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            _join(address(this), looseAsset);
        }
        _invested = _balanceAsset() + _balanceUpdatedDSR();
    }

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

    function _balanceDSR() internal view returns (uint256) {
        return pot.pie(address(this)) * pot.chi() / RAY;
    }

    function _balanceUpdatedDSR() internal returns (uint256) {
        uint256 chi = (block.timestamp > pot.rho()) ? pot.drip() : pot.chi();
        return _rmul(chi, pot.pie(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    function balanceDSR() external view returns (uint256) {
        return _balanceDSR();
    }

    function balanceUpdatedDSR() external returns (uint256) {
        return _balanceUpdatedDSR();
    }

    function emergencyWithdraw(uint256 _amount) external onlyManagement {
        //lendingPool.withdraw(asset, _amount, address(this));
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
}

interface PotLike {
    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;
    function vat() external view returns (address);
    function pie(address) external view returns (uint256);
}

