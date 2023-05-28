// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICrvV3 is IERC20 {
    function minter() external view returns (address);

}
