//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

/**
 * @title StakeManager interface
 */
interface IStakeManager {
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

    function calcPTAmount(uint256 amountInNativeYieldToken, uint256 amountInYT) external view returns (uint256);


    /** setter **/
    function setBurnedYTFeeRate(uint256 _burnedYTFeeRate) external;

    function setForceUnstakeFeeRate(uint256 _forceUnstakeFeeRate) external;

    function setMinLockupDays(uint128 _minLockupDays) external;

    function setMaxLockupDays(uint128 _maxLockupDays) external;


    /** function **/
    function initialize(
        uint256 burnedYTFeeRate_, 
        uint256 forceUnstakeFeeRate_, 
        uint128 minLockupDays_, 
        uint128 maxLockupDays_
    ) external;

    function stake(
        uint256 stakedAmount, 
        uint256 lockupDays, 
        address positionOwner, 
        address ptRecipient, 
        address ytRecipient
    ) external returns (uint256 amountInPT, uint256 amountInYT);

    function unstake(uint256 positionId, uint256 share) external;

    function withdrawYield(uint256 amountInREY) external returns (uint256 yieldAmount);

    function accumYieldPool(uint256 nativeYield) external;


    /** event **/
    event Stake(
        uint256 indexed positionId,
        uint256 amountInNativeYieldToken,
        uint256 amountInPT,
        uint256 amountInYT,
        uint256 deadline
    );

    event Unstake(
        uint256 indexed positionId, 
        uint256 amountInNativeYieldToken, 
        uint256 amountInBurnedPT, 
        uint256 amountInBurnedYT, 
        uint256 forceUnstakeFee
    );

    event WithdrawYield(address indexed account, uint256 amountInBurnedYT, uint256 yieldAmount);

    event SetBurnedYTFeeRate(uint256 burnedYTFeeRate);

    event SetForceUnstakeFeeRate(uint256 forceUnstakeFeeRate);

    event SetMinLockupDays(uint128 minLockupDays);

    event SetMaxLockupDays(uint128 maxLockupDays);
}