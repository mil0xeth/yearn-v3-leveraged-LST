// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IStrategy, IUniswapV3Swapper {
    function initializeAaveV3Lender(address _asset) external;

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function manualRedeemAave() external;

    function emergencyWithdraw(uint256 _amount) external;

    function cloneAaveV3Lender(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external returns (address newLender);

    function aToken() external view returns (address);
    function balanceAsset() external view returns (uint256);
    function balanceCollateral() external view returns (uint256);
    function balanceCRVDebt() external view returns (uint256);
    function balanceSTYCRVDebt() external view returns (uint256);
    function CRVToAsset(uint256 _CRVAmount) external view returns (uint256);
    function STYCRVToCRV(uint256 _STYCRVAmount) external view returns (uint256);
    function STYCRVToAsset(uint256 _STYCRVAmount) external view returns (uint256);
}
