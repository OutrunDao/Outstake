// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./interfaces/IRUSD.sol";
import "../../vault/interfaces/IOutUSDBVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title Outrun USD Wrapped Token
 */
contract RUSD is IRUSD, ERC20, Ownable {
    using SafeERC20 for IERC20;

    address public constant USDB = 0x4200000000000000000000000000000000000022;
    address public outUSDBVault;

    modifier onlyOutUSDBVault() {
        require(msg.sender == outUSDBVault, "Access only by OutUSDBVault");
        _;
    }

    constructor(address owner) ERC20("Outrun Wrapped USDB", "RUSD") Ownable(owner) {}

    /**
     * @dev Allows user to deposit USDB and mint RUSD
     * @notice User must have approved this contract to spend USDB
     */
    function deposit(uint256 amount) external override {
        require(amount > 0, "Invalid Amount");
        address user = msg.sender;
        IERC20(USDB).safeTransferFrom(user, outUSDBVault, amount);
        _mint(user, amount);

        emit Deposit(user, amount);
    }

        /**
     * @dev Allows user to withdraw USDB by RUSD
     * @param amount - Amount of RUSD for burn
     */
    function withdraw(uint256 amount) external override {
        require(amount > 0, "Invalid Amount");
        address user = msg.sender;
        _burn(user, amount);
        IOutUSDBVault(outUSDBVault).withdraw(user, amount);

        emit Withdraw(user, amount);
    }

    function mint(address _account, uint256 _amount) external override onlyOutUSDBVault {
        _mint(_account, _amount);
    }
    
    function setOutUSDBVault(address _outUSDBVault) external override onlyOwner {
        outUSDBVault = _outUSDBVault;
        emit SetOutUSDBVault(_outUSDBVault);
    }
}