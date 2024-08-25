// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

 /**
  * @title ORUSD interface
  */
interface IORUSD is IERC20 {
	struct FlashLoanFeeRate {
		uint128 providerFeeRate;
		uint128 protocolFeeRate;
	}

	error ZeroInput();

	error PermissionDenied();

	error FeeRateOverflow();

	error FlashLoanRepayFailed();


    function ORUSDStakeManager() external view returns (address);

    function revenuePool() external view returns (address);

    function protocolFeeRate() external view returns (uint256);

    function flashLoanFeeRate() external view returns (FlashLoanFeeRate memory);


    function setAutoBot(address _bot) external;
    
    function setProtocolFeeRate(uint256 _protocolFeeRate) external;

    function setFlashLoanFeeRate(uint128 _providerFeeRate, uint128 _protocolFeeRate) external;

    function setRevenuePool(address _pool) external;

    function setORUSDStakeManager(address _orUSDStakeManager) external;


    function initialize(address stakeManager_) external;

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function accumUSDBYield() external returns (uint256 nativeYield, uint256 dayRate);

    function flashLoan(address receiver, uint256 amount, bytes calldata data) external;


    event SetAutoBot(address _bot);

	event SetORUSDStakeManager(address _orUSDStakeManager);

	event SetRevenuePool(address _pool);

    event SetProtocolFeeRate(uint256 _protocolFeeRate);

    event SetFlashLoanFeeRate(uint128 _providerFeeRate, uint128 _protocolFeeRate);

	event Deposit(address indexed _account, uint256 _amount);

    event Withdraw(address indexed _account, uint256 _amount);

	event AccumUSDBYield(uint256 amount, uint256 dayRate);
    
    event FlashLoan(address indexed receiver, uint256 amount, uint256 providerFeeAmount, uint256 protocolFeeAmount);
}