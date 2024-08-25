// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

 /**
  * @title Outrun ETH yield token interface
  */
interface IREY is IERC20 {
	error ZeroInput();

	error PermissionDenied();

	function ORETHStakeManager() external view returns (address);

	function initialize(address stakeManager_) external;

	function mint(address _account, uint256 _amount) external;

	function burn(address _account, uint256 _amount) external;

	function setORETHStakeManager(address _stakeManager) external;

	event SetORETHStakeManager(address  _stakeManager);
}