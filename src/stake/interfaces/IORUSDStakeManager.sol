//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

/**
 * @title ORUSDStakeManager interface
 */
interface IORUSDStakeManager {
    function handleUSDBYield(uint256 protocolFeeRate, address revenuePool) external returns (uint256);
}