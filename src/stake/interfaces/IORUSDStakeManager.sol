//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

/**
 * @title IORUSDStakeManager interface
 */
interface IORUSDStakeManager {
    /** error **/
    error ZeroInput();

    error PermissionDenied();

    error MinStakeInsufficient(uint256 minStake);

    error InvalidLockupDays(uint256 minLockupDays, uint256 maxLockupDays);
    
    error FeeRateOverflow();
    

    /** view **/
    function burnedYTFeeRate() external view returns (uint256);

    function forceUnstakeFeeRate() external view returns (uint256);

    function totalStaked() external view returns (uint256);

    function totalYieldPool() external view returns (uint256);

    function minLockupDays() external view returns (uint128);

    function maxLockupDays() external view returns (uint128);

    function avgStakeDays() external view returns (uint256);

    function calcOSUSDAmount(uint256 amountInORUSD, uint256 amountInRUY) external view returns (uint256);


    /** setter **/
    function setBurnedYTFeeRate(uint256 _burnedYTFeeRate) external;

    function setForceUnstakeFeeRate(uint256 _forceUnstakeFeeRate) external;

    function setMinLockupDays(uint128 _minLockupDays) external;

    function setMaxLockupDays(uint128 _maxLockupDays) external;


    /** function **/
    function initialize(
        uint256 forceUnstakeFeeRate_, 
        uint256 burnedYTFeeRate_, 
        uint128 minLockupDays_, 
        uint128 maxLockupDays_
    ) external;

    function stake(
        uint256 amountInORUSD, 
        uint256 lockupDays, 
        address positionOwner, 
        address osUSDTo, 
        address ruyTo
    ) external returns (uint256 amountInOSUSD, uint256 amountInRUY);

    function unstake(uint256 positionId, uint256 share) external;

    function withdrawYield(uint256 amountInRUY) external returns (uint256 yieldAmount);

    function handleUSDBYield(
        uint256 protocolFeeRate, 
        address revenuePool
    ) external returns (uint256);

    function accumYieldPool(uint256 nativeYield) external;

    /** event **/
    event StakeORUSD(
        uint256 indexed positionId,
        uint256 amountInORUSD,
        uint256 amountInOSUSD,
        uint256 amountInRUY,
        uint256 deadline
    );

    event Unstake(uint256 indexed positionId, uint256 amountInORUSD, uint256 burnedOSUSD, uint256 burnedRUY);

    event WithdrawYield(address indexed account, uint256 burnedRUY, uint256 yieldAmount);

    event SetBurnedYTFeeRate(uint256 burnedYTFeeRate);
    
    event SetForceUnstakeFeeRate(uint256 forceUnstakeFeeRate);

    event SetMinLockupDays(uint128 minLockupDays);

    event SetMaxLockupDays(uint128 maxLockupDays);
}