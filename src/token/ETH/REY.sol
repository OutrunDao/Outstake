// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IREY.sol";
import "../../blast/GasManagerable.sol";
import "../../utils/Initializable.sol";

/**
 * @title Outrun ETH yield token
 */
contract REY is IREY, ERC20, Initializable, Ownable, GasManagerable {
    address public _orETHStakeManager;

    modifier onlyORETHStakeManager() {
        require(msg.sender == _orETHStakeManager, PermissionDenied());
        _;
    }

    constructor(address owner, address gasManager_) ERC20("Outrun ETH yield token", "REY") Ownable(owner) GasManagerable(gasManager_) {}

    function ORETHStakeManager() external view override returns (address) {
        return _orETHStakeManager;
    }

    /**
     * @dev Initializer
     * @param stakeManager_ - Address of orETHStakeManager
     */
    function initialize(address stakeManager_) external override initializer {
        setORETHStakeManager(stakeManager_);
    }

    /**
     * @dev Only orETHStakeManager can mint when the user stake orETH
     * @param _account Address who stake orETH 
     * @param _amount The amount of minted REY
     */
    function mint(address _account, uint256 _amount) external override onlyORETHStakeManager {
        _mint(_account, _amount);
    }

    /**
     * @dev Only orETHStakeManager can burn when the user redempt the native yield
     * @param _account Address who redempt the native yield
     * @param _amount The amount of burned REY
     */
    function burn(address _account, uint256 _amount) external override onlyORETHStakeManager {
        _burn(_account, _amount);
    }

    function setORETHStakeManager(address _stakeManager) public override onlyOwner {
        _orETHStakeManager = _stakeManager;
        emit SetORETHStakeManager(_stakeManager);
    }
}