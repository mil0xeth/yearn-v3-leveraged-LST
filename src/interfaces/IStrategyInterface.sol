// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IStrategy {
    function balanceOfAsset() external view returns (uint256);
    function balanceOfLST() external view returns (uint256);
    function balanceOfCollateral() external view returns (uint256);
    function balanceOfDebt() external view returns (uint256);
    function LST() external view returns (address);
    function maxSingleTrade() external view returns (uint256);
    function targetLoanToValue() external view returns (uint256);
    function windLoanToValue() external view returns (uint256);
    function unwindLoanToValue() external view returns (uint256);
    function pool() external view returns(address);
    function getAssetPerLST() external view returns (uint256);

    function currentLoanToValue() external view returns (uint256);

    function setSwapSlippage(uint256) external;
    function setProfitLimitRatio(uint256) external;
    function setLossLimitRatio(uint256) external;

    function setMaxSingleTrade(uint256) external;
    function setMaxSingleWithdraw(uint256) external;
}
