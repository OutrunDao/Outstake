//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../stake/interfaces/IRUSDStakeManager.sol";
import "../blast/IERC20Rebasing.sol";
import "./interfaces/IOutUSDBVault.sol";
import "../token/USDB//interfaces/IRUSD.sol";
import {BlastModeEnum} from "../blast/BlastModeEnum.sol";

/**
 * @title USDB Vault Contract
 */
contract OutUSDBVault is IOutUSDBVault, Ownable, BlastModeEnum {
    using SafeERC20 for IERC20;

    address public constant USDB = 0x4200000000000000000000000000000000000022;
    uint256 public constant THOUSAND = 1000;

    address public immutable rUSD;
    address public RUSDStakeManager;
    address public revenuePool;
    uint256 public feeRate;

    modifier onlyRUSDContract() {
        require(msg.sender == rUSD, "Only RUSD contract");
        _;
    }

    /**
     * @param _owner - Address of the owner
     * @param _rUSD - Address of RUSD Token
     * @param _revenuePool - Revenue pool
     * @param _RUSDStakeManager - RUSD stake manager
     * @param _feeRate - Fee to revenue pool
     */
    constructor(
        address _owner,
        address _rUSD,
        address _revenuePool,
        address _RUSDStakeManager,
        uint256 _feeRate
    ) Ownable(_owner) {
        require(_feeRate <= THOUSAND, "FeeRate must not exceed (100%)");

        rUSD = _rUSD;
        feeRate = _feeRate;
        revenuePool = _revenuePool;
        RUSDStakeManager = _RUSDStakeManager;

        emit SetFeeRate(_feeRate);
        emit SetRevenuePool(_revenuePool);
        emit SetRUSDStakeManager(_RUSDStakeManager);
    }

    /**
     * @dev Initialize native yield claimable
     */
    function initialize() external override {
        IERC20Rebasing(USDB).configure(YieldMode.CLAIMABLE);
    }

    /**
     * @dev When user withdraw by RUSD contract
     * @param user - Address of User
     * @param amount - Amount of USDB for withdraw
     */
    function withdraw(address user, uint256 amount) external override onlyRUSDContract {
        IERC20(USDB).safeTransfer(user, amount);
    }

    /**
     * @dev Claim USDB yield to this contract
     */
    function claimUSDBYield() public override {
        uint256 yieldAmount = IERC20Rebasing(USDB).getClaimableAmount(address(this));
        if (yieldAmount > 0) {
            IERC20Rebasing(USDB).claim(address(this), yieldAmount);
            if (feeRate > 0) {
                uint256 feeAmount = Math.mulDiv(yieldAmount, feeRate, THOUSAND);
                require(revenuePool != address(0), "revenue pool not set");
                IERC20(USDB).safeTransfer(revenuePool, feeAmount);
                yieldAmount -= feeAmount;
            }

            IRUSD(rUSD).mint(RUSDStakeManager, yieldAmount);
            IRUSDStakeManager(RUSDStakeManager).updateYieldAmount(yieldAmount);

            emit ClaimUSDBYield(yieldAmount);
        }
    }

    function setFeeRate(uint256 _feeRate) external override onlyOwner {
        require(_feeRate <= THOUSAND, "FeeRate must not exceed (100%)");

        feeRate = _feeRate;
        emit SetFeeRate(_feeRate);
    }

    function setRevenuePool(address _pool) external override onlyOwner {
        revenuePool = _pool;
        emit SetRevenuePool(_pool);
    }

    function setRUSDStakeManager(address _RUSDStakeManager) external override onlyOwner {
        RUSDStakeManager = _RUSDStakeManager;
        emit SetRUSDStakeManager(_RUSDStakeManager);
    }
}