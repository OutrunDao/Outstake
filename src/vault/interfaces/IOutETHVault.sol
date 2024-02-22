//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IOutETHVault {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function claimETHYield() external;

    function setFeeRate(uint256 _feeRate) external;

    function setRevenuePool(address _pool) external;

    function setYieldPool(address _pool) external;

    event Deposit(address indexed _account, uint256 _amount);

    event Withdraw(address indexed _account, uint256 _amount);

    event ClaimETHYield(uint256 amount);

    event SetFeeRate(uint256 _feeRate);

    event SetBot(address _bot);

    event SetRevenuePool(address _address);

    event SetYieldPool(address _address);
}