// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IRUY.sol";
import "../../blast/GasManagerable.sol";
import "../../utils/Initializable.sol";

/**
 * @title Outrun USD yield token
 */
contract RUY is IRUY, ERC20, Initializable, Ownable, GasManagerable {
    address private _orUSDStakeManager;

    modifier onlyORUSDStakeManager() {
        require(msg.sender == _orUSDStakeManager, PermissionDenied());
        _;
    }

    constructor(address owner, address gasManager_) ERC20("Outrun USD yield token", "RUY") Ownable(owner) GasManagerable(gasManager_) {}

    function ORUSDStakeManager() external view override returns (address) {
        return _orUSDStakeManager;
    }

    /**
     * @dev Initializer
     * @param stakeManager_ - Address of orUSDStakeManager
     */
    function initialize(address stakeManager_) external override initializer {
        setORUSDStakeManager(stakeManager_);
    }

    /**
     * @dev Only orUSDStakeManager can mint when the user stake orUSD
     * @param _account Address who stake orUSD 
     * @param _amount The amount of minted RUY
     */
    function mint(address _account, uint256 _amount) external override onlyORUSDStakeManager {
        _mint(_account, _amount);
    }

    /**
     * @dev Only orUSDStakeManager can burn when the user redempt the native yield
     * @param _account Address who redempt the native yield
     * @param _amount The amount of burned RUY
     */
    function burn(address _account, uint256 _amount) external override onlyORUSDStakeManager {
        _burn(_account, _amount);
    }

    function setORUSDStakeManager(address _stakeManager) public override onlyOwner {
        _orUSDStakeManager = _stakeManager;
        emit SetORUSDStakeManager(_stakeManager);
    }
}