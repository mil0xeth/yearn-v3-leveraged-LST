// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}
