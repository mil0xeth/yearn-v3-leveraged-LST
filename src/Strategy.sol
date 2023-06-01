// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/maker/IMaker.sol";

contract Strategy is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;

    uint256 internal constant RAY = 1e27;

    PotLike internal constant pot = PotLike(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    DaiJoinLike internal constant daiJoin = DaiJoinLike(0x9759A6Ac90977b93B58547b4A71c78317f391A28);

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        initializeStrategy(_asset);
    }

    function initializeStrategy(address _asset) public {
        require(ERC20(_asset).allowance(address(this), address(daiJoin)) == 0, "already initialized");
        //approvals:
        ERC20(_asset).safeApprove(address(daiJoin), type(uint256).max);
        
        //approve Maker internal accounting moves of DAI
        VatLike vat = VatLike(pot.vat());
        vat.hope(address(daiJoin));
        vat.hope(address(pot));
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _invest(uint256 _amount) internal override {
        _join(_amount);
    }

    function _join(uint256 wad) internal {
        //summary: strategy invests DAI into Maker's DSR
        //
        //Maker vocabulary:
        //pot: DSR core contract
        //chi: the DSR DAI balance rate accumulator, needs to be updated with .drip()
        //drip(): calculates most recent DAI and DSR shares amount (updates chi)
        //rho: the last time that drip is called.
        //pie: the strategy's final shares in the DSR (pot) 
        //daiJoin: the DAI ERC20 token system
        //daiJoin.join(): send DAI amount (wad) into Maker internal accounting system
        //pot.join(): claim DAI amount into the DSR as shares
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

    function _freeFunds(uint256 _amount) internal override {
        _exit(_amount);
    }

    function _exit(uint256 wad) internal {
        //summary: strategy withdraws DAI from Maker's DSR
        //
        //Maker vocabulary:
        //pot: DSR core contract
        //chi: the DSR DAI balance rate accumulator, needs to be updated with .drip()
        //drip(): calculates most recent DAI and DSR shares amount (updates chi)
        //rho: the last time that drip is called
        //pie: the strategy's final shares in the DSR (pot)
        //pot.exit(): redeem shares of DSR into DAI amount in Maker's internal accounting system 
        //daiJoin: the DAI ERC20 token system
        //daiJoin.exit(): retrieve DAI amount (wad) from Maker internal accounting system into the strategy
        uint256 chi = (block.timestamp > pot.rho()) ? pot.drip() : pot.chi();
        uint256 pie = _rdivup(wad, chi);
        pie = Math.min(pot.pie(address(this)), pie);
        pot.exit(pie);
        uint256 amt = _rmul(chi, pie);
        daiJoin.exit(address(this), amt);
    }
    
    function _rdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds up
        z = ( x * RAY + (y - 1) ) / y;
    }

    function _totalInvested() internal override returns (uint256 _invested) {
        // deposit any loose DAI funds in the strategy
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            _join(looseAsset);
        }
        //total assets of the strategy:
        _invested = _balanceAsset() + _balanceUpdatedDSR();
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL:
    //////////////////////////////////////////////////////////////*/

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    //strategy's DSR balance: always up-to-date
    function _balanceUpdatedDSR() internal returns (uint256) {
        //summary: check if DSR rate accumulator is up-to-date (& update if not) & get balance of strategy's deposited DAI
        //
        //Maker vocabulary:
        //pot: DSR core contract
        //chi: the DSR DAI balance rate accumulator, needs to be updated with .drip()
        //rho: the last time that drip is called
        uint256 chi = (block.timestamp > pot.rho()) ? pot.drip() : pot.chi();
        return _rmul(chi, pot.pie(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    //strategy's DSR balance: always up-to-date
    function balanceUpdatedDSR() external returns (uint256) {
        return _balanceUpdatedDSR();
    }

    //strategy's approximate DSR balance, potentially not up-to-date: just for external view checks of approximate total assets of the strategy
    function balanceDSR() external view returns (uint256) {
        return pot.pie(address(this)) * pot.chi() / RAY;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY:
    //////////////////////////////////////////////////////////////*/

    //emergency withdraw DAI amount from DSR into strategy
    function emergencyWithdraw(uint256 _amount) external onlyManagement {
        _exit(_amount);
    }

    //emergency withdraw all DAI from DSR into strategy
    function emergencyWithdrawAll() external onlyManagement {
        _exit(_balanceUpdatedDSR());
        //Management needs to call afterwards:
        //shutdownStrategy()
        //report()
    }

    function cloneStrategy(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external returns (address newStrategy) {
        newStrategy = TokenizedStrategy.clone(
            _asset,
            _name,
            _management,
            _performanceFeeRecipient,
            _keeper
        );
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

