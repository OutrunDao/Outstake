//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import "./PositionOptionsToken.sol";
import "../utils/Initializable.sol";
import "../utils/AutoIncrementId.sol";
import "../token/ETH/interfaces/IREY.sol";
import "../token/ETH/interfaces/IORETH.sol";
import "../token/ETH/interfaces/IOSETH.sol";
import "../blast/GasManagerable.sol";
import "./interfaces/IORETHStakeManager.sol";

/**
 * @title ORETH Stake Manager Contract
 * @dev Handles Staking of orETH
 */
contract ORETHStakeManager is IORETHStakeManager, PositionOptionsToken, Initializable, Ownable, GasManagerable, AutoIncrementId {
    using SafeERC20 for IERC20;

    uint256 public constant RATIO = 10000;
    uint256 public constant MINSTAKE = 1e16;
    uint256 public constant DAY = 24 * 3600;

    address public immutable ORETH;
    address public immutable OSETH;
    address public immutable REY;

    uint256 private _burnedYTFeeRate;
    uint256 private _forceUnstakeFeeRate;
    uint256 private _totalStaked;
    uint256 private _totalYieldPool;
    uint128 private _minLockupDays;
    uint128 private _maxLockupDays;

    /**
     * @param owner - Address of owner
     * @param gasManager_ - Address of gas manager
     * @param orETH - Address of orETH Token
     * @param osETH - Address of osETH Token
     * @param rey - Address of REY Token
     */
    constructor(
        address owner, 
        address gasManager_, 
        address orETH, 
        address osETH, 
        address rey,
        string memory uri
    ) ERC1155(uri) Ownable(owner) GasManagerable(gasManager_) {
        ORETH = orETH;
        OSETH = osETH;
        REY = rey;
    }


    /** view **/
    function burnedYTFeeRate() external view override returns (uint256) {
        return _burnedYTFeeRate;
    }

    function forceUnstakeFeeRate() external view override returns (uint256) {
        return _forceUnstakeFeeRate;
    }

    function totalStaked() external view override returns (uint256) {
        return _totalStaked;
    }

    function totalYieldPool() external view override returns (uint256) {
        return _totalYieldPool;
    }

    function minLockupDays() external view override returns (uint128) {
        return _minLockupDays;
    }

    function maxLockupDays() external view override returns (uint128) {
        return _maxLockupDays;
    }

    function avgStakeDays() public view override returns (uint256) {
        return IERC20(REY).totalSupply() / _totalStaked;
    }

    function calcOSETHAmount(uint256 amountInORETH, uint256 amountInREY) public view override returns (uint256) {
        return amountInORETH - (amountInREY * _totalYieldPool / IERC20(REY).totalSupply());
    }


    /** setter **/
    /**
     * @param burnedYTFeeRate_ - Burn more YT when force unstake
     */
    function setBurnedYTFeeRate(uint256 burnedYTFeeRate_) public override onlyOwner {
        require(burnedYTFeeRate_ <= RATIO, FeeRateOverflow());

        _burnedYTFeeRate = burnedYTFeeRate_;
        emit SetBurnedYTFeeRate(burnedYTFeeRate_);
    }

    /**
     * @param forceUnstakeFeeRate_ - Force unstake fee rate
     */
    function setForceUnstakeFeeRate(uint256 forceUnstakeFeeRate_) public override onlyOwner {
        require(forceUnstakeFeeRate_ <= RATIO, FeeRateOverflow());

        _forceUnstakeFeeRate = forceUnstakeFeeRate_;
        emit SetForceUnstakeFeeRate(forceUnstakeFeeRate_);
    }

    /**
     * @param minLockupDays_ - Min lockup days
     */
    function setMinLockupDays(uint128 minLockupDays_) public override onlyOwner {
        _minLockupDays = minLockupDays_;
        emit SetMinLockupDays(minLockupDays_);
    }

    /**
     * @param maxLockupDays_ - Max lockup days
     */
    function setMaxLockupDays(uint128 maxLockupDays_) public override onlyOwner {
        _maxLockupDays = maxLockupDays_;
        emit SetMaxLockupDays(maxLockupDays_);
    }

    
    /** function **/
    /**
     * @dev Initializer
     * @param burnedYTFeeRate_ - Burn more YT when force unstake
     * @param forceUnstakeFeeRate_ - Force unstake fee
     * @param minLockupDays_ - Min lockup days
     * @param maxLockupDays_ - Max lockup days
     */
    function initialize(
        uint256 burnedYTFeeRate_,
        uint256 forceUnstakeFeeRate_, 
        uint128 minLockupDays_, 
        uint128 maxLockupDays_
    ) external override initializer {
        setBurnedYTFeeRate(burnedYTFeeRate_);
        setForceUnstakeFeeRate(forceUnstakeFeeRate_);
        setMinLockupDays(minLockupDays_);
        setMaxLockupDays(maxLockupDays_);
    }

    /**
     * @dev Allows user to deposit orETH, then mints osETH and REY for the user.
     * @param amountInORETH - orETH staked amount
     * @param lockupDays - User can withdraw after lockupDays
     * @param positionOwner - Owner of position
     * @param osETHTo - Receiver of osETH
     * @param reyTo - Receiver of REY
     * @notice User must have approved this contract to spend orETH
     */
    function stake(
        uint256 amountInORETH, 
        uint256 lockupDays, 
        address positionOwner, 
        address osETHTo, 
        address reyTo
    ) external override returns (uint256 amountInOSETH, uint256 amountInREY) {
        require(amountInORETH >= MINSTAKE, MinStakeInsufficient(MINSTAKE));
        require(
            lockupDays >= _minLockupDays && lockupDays <= _maxLockupDays, 
            InvalidLockupDays(_minLockupDays, _maxLockupDays)
        );

        address msgSender = msg.sender;
        uint256 deadline;
        unchecked {
            _totalStaked += amountInORETH;
            deadline = block.timestamp + lockupDays * DAY;
            amountInREY = amountInORETH * lockupDays;
        }

        IREY(REY).mint(reyTo, amountInREY);
        amountInOSETH = calcOSETHAmount(amountInORETH, amountInREY);
        uint256 positionId = _nextId();
        positions[positionId] = Position(ORETH, amountInORETH, amountInOSETH, deadline);

        _mint(positionOwner, positionId, amountInORETH, "");
        IERC20(ORETH).safeTransferFrom(msgSender, address(this), amountInORETH);
        IOSETH(OSETH).mint(osETHTo, amountInOSETH);

        emit StakeORETH(positionId, amountInORETH, amountInOSETH, amountInREY, deadline);
    }

    /**
     * @dev Allows user to unstake funds. If force unstake, need to pay force unstake fee.
     * @param positionId - Staked ETH Position Id
     * @param share - Share of the position
     */
    function unstake(uint256 positionId, uint256 share) external override {
        address msgSender = msg.sender;
        burn(msgSender, positionId, share);
        
        Position storage position = positions[positionId];
        uint256 stakedAmount = position.stakedAmount;
        uint256 PTAmount = position.PTAmount;
        uint256 deadline = position.deadline;
        uint256 burnedOSETH = Math.mulDiv(PTAmount, share, stakedAmount, Math.Rounding.Ceil);
        IOSETH(OSETH).burn(msgSender, burnedOSETH);
        unchecked {
            _totalStaked -= share;
        }
        
        uint256 burnedREY;
        uint256 forceUnstakeFee;
        uint256 currentTime = block.timestamp;
        if (deadline > currentTime) {
            unchecked {
                burnedREY = share * Math.ceilDiv(deadline - currentTime, DAY) * (RATIO + _burnedYTFeeRate) / RATIO;
            }
            IREY(REY).burn(msgSender, burnedREY);
            position.deadline = currentTime;

            unchecked {
                forceUnstakeFee = share * _forceUnstakeFeeRate / RATIO;
                share -= forceUnstakeFee;
            }
            IORETH(ORETH).withdraw(forceUnstakeFee);
            Address.sendValue(payable(IORETH(ORETH).revenuePool()), forceUnstakeFee);
        }        
        IERC20(ORETH).safeTransfer(msgSender, share);

        emit Unstake(positionId, share, burnedOSETH, burnedREY, forceUnstakeFee);
    }

    /**
     * @dev Allows user burn REY to withdraw yield
     * @param burnedREY - Amount of burned REY
     */
    function withdrawYield(uint256 burnedREY) external override returns (uint256 yieldAmount) {
        require(burnedREY != 0, ZeroInput());

        unchecked {
            yieldAmount = _totalYieldPool * burnedREY / IREY(REY).totalSupply();
            _totalYieldPool -= yieldAmount;
        }

        address msgSender = msg.sender;
        IREY(REY).burn(msgSender, burnedREY);
        IERC20(ORETH).safeTransfer(msgSender, yieldAmount);

        emit WithdrawYield(msgSender, burnedREY, yieldAmount);
    }

    /**
     * @dev Accumulate the native yield
     * @param nativeYield - Additional native yield amount
     */
    function accumYieldPool(uint256 nativeYield) external override {
        require(msg.sender == ORETH, PermissionDenied());

        unchecked {
            _totalYieldPool += nativeYield;
        }
    }
}
