//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRETHStakeManager.sol";
import "../vault/interfaces/IOutETHVault.sol";
import "../utils/Math.sol";
import "../utils/AutoIncrementId.sol";
import "../token/ETH/interfaces/IREY.sol";
import "../token/ETH/interfaces/IRETH.sol";
import "../token/ETH/interfaces/IPETH.sol";

/**
 * @title RETH Stake Manager Contract
 * @dev Handles Staking of RETH
 */
contract RETHStakeManager is IRETHStakeManager, Ownable, AutoIncrementId {
    using SafeERC20 for IERC20;

    uint256 public constant RATIO = 10000;
    uint256 public constant MINSTAKE = 1e16;
    uint256 public constant DAY = 24 * 3600;

    address public immutable rETH;
    address public immutable pETH;
    address public immutable rey;

    address private _outETHVault;
    uint256 private _forceUnstakeFee;
    uint256 private _totalStaked;
    uint256 private _totalYieldPool;
    uint16 private _minLockupDays;
    uint16 private _maxLockupDays;

    mapping(uint256 positionId => Position) private _positions;

    modifier onlyOutETHVault() {
        if (msg.sender != _outETHVault) {
            revert PermissionDenied();
        }
        _;
    }

    /**
     * @param owner_ - Address of the owner
     * @param rETH_ - Address of RETH Token
     * @param pETH_ - Address of PETH Token
     * @param rey_ - Address of REY Token
     * @param outETHVault_ - Address of OutETHVault
     */
    constructor(address owner_, address rETH_, address pETH_, address rey_, address outETHVault_) Ownable(owner_) {
        rETH = rETH_;
        pETH = pETH_;
        rey = rey_;
        _outETHVault = outETHVault_;

        emit SetOutETHVault(outETHVault_);
    }

    /**
     * view *
     */
    function outETHVault() external view override returns (address) {
        return _outETHVault;
    }

    function forceUnstakeFee() external view override returns (uint256) {
        return _forceUnstakeFee;
    }

    function totalStaked() external view override returns (uint256) {
        return _totalStaked;
    }

    function totalYieldPool() external view override returns (uint256) {
        return _totalYieldPool;
    }

    function minLockupDays() external view override returns (uint16) {
        return _minLockupDays;
    }

    function maxLockupDays() external view override returns (uint16) {
        return _maxLockupDays;
    }

    function positionsOf(uint256 positionId) external view override returns (Position memory) {
        return _positions[positionId];
    }

    function getStakedRETH() public view override returns (uint256) {
        return IRETH(rETH).balanceOf(address(this));
    }

    function avgStakeDays() public view override returns (uint256) {
        return IERC20(rey).totalSupply() / _totalStaked;
    }

    function calcPETHAmount(uint256 amountInRETH) public view override returns (uint256) {
        uint256 totalShares = IRETH(pETH).totalSupply();
        totalShares = totalShares == 0 ? 1 : totalShares;

        uint256 yieldVault = getStakedRETH();
        yieldVault = yieldVault == 0 ? 1 : yieldVault;

        unchecked {
            return amountInRETH * totalShares / yieldVault;
        }
    }

    /**
     * function *
     */
    /**
     * @dev Allows user to deposit RETH, then mints PETH and REY for the user.
     * @param amountInRETH - RETH staked amount, amount % 1e15 == 0
     * @param lockupDays - User can withdraw after lockupDays
     * @param positionOwner - Owner of position
     * @param receiver - Receiver of PETH and REY
     * @notice User must have approved this contract to spend RETH
     */
    function stake(uint256 amountInRETH, uint16 lockupDays, address positionOwner, address receiver)
        external
        override
        returns (uint256, uint256)
    {
        if (amountInRETH < MINSTAKE) {
            revert MinStakeInsufficient(MINSTAKE);
        }
        if (lockupDays < _minLockupDays || lockupDays > _maxLockupDays) {
            revert InvalidLockupDays(_minLockupDays, _maxLockupDays);
        }

        address msgSender = msg.sender;
        uint256 amountInPETH = calcPETHAmount(amountInRETH);
        uint256 positionId = nextId();
        uint256 deadline;
        uint256 amountInREY;
        unchecked {
            _totalStaked += amountInRETH;
            deadline = block.timestamp + lockupDays * DAY;
            amountInREY = amountInRETH * lockupDays;
        }
        _positions[positionId] =
            Position(uint96(amountInRETH), uint96(amountInPETH), uint56(deadline), false, positionOwner);

        IERC20(rETH).safeTransferFrom(msgSender, address(this), amountInRETH);
        IPETH(pETH).mint(receiver, amountInPETH);
        IREY(rey).mint(receiver, amountInREY);

        emit StakeRETH(positionId, positionOwner, amountInRETH, deadline);

        return (amountInPETH, amountInREY);
    }

    /**
     * @dev Allows user to unstake funds. If force unstake, need to pay force unstake fee.
     * @param positionId - Staked Principal Position Id
     */
    function unstake(uint256 positionId) external returns (uint256) {
        address msgSender = msg.sender;
        Position storage position = _positions[positionId];
        if (position.closed) {
            revert PositionClosed();
        }
        if (position.owner != msgSender) {
            revert PermissionDenied();
        }

        position.closed = true;
        uint256 amountInRETH = position.RETHAmount;
        unchecked {
            _totalStaked -= amountInRETH;
        }
        IPETH(pETH).burn(msgSender, position.PETHAmount);

        uint256 deadline = position.deadline;
        uint256 currentTime = block.timestamp;
        if (deadline > currentTime) {
            uint256 amountInREY;
            unchecked {
                amountInREY = amountInRETH * Math.ceilDiv(deadline - currentTime, DAY);
            }
            IREY(rey).burn(msgSender, amountInREY);
            position.deadline = uint56(currentTime);

            uint256 fee;
            unchecked {
                fee = amountInRETH * _forceUnstakeFee / RATIO;
                amountInRETH -= fee;
            }
            IRETH(rETH).withdraw(fee);
            Address.sendValue(payable(IOutETHVault(_outETHVault).revenuePool()), fee);
        }        
        IERC20(rETH).safeTransfer(msgSender, amountInRETH);

        emit Unstake(positionId, msgSender, amountInRETH);

        return amountInRETH;
    }

    /**
     * @dev Allows user to extend lock time
     * @param positionId - Staked Principal Position Id
     * @param extendDays - Extend lockup days
     */
    function extendLockTime(uint256 positionId, uint256 extendDays) external returns (uint256) {
        address user = msg.sender;
        Position memory position = _positions[positionId];
        if (position.owner != user) {
            revert PermissionDenied();
        }
        uint256 currentTime = block.timestamp;
        uint256 deadline = position.deadline;
        if (deadline <= currentTime) {
            revert ReachedDeadline(deadline);
        }
        uint256 newDeadLine = deadline + extendDays * DAY;
        uint256 intervalDaysFromNow = (newDeadLine - currentTime) / DAY;
        if (intervalDaysFromNow < _minLockupDays || intervalDaysFromNow > _maxLockupDays) {
            revert InvalidExtendDays();
        }
        position.deadline = uint56(newDeadLine);

        uint256 amountInREY;
        unchecked {
            amountInREY = position.RETHAmount * extendDays;
        }
        IREY(rey).mint(user, amountInREY);

        emit ExtendLockTime(positionId, extendDays, amountInREY);

        return amountInREY;
    }

    /**
     * @dev Allows user burn REY to  withdraw yield
     * @param amountInREY - Amount of REY
     */
    function withdrawYield(uint256 amountInREY) external override returns (uint256) {
        if (amountInREY == 0) {
            revert ZeroInput();
        }

        IOutETHVault(_outETHVault).claimETHYield();
        uint256 yieldAmount;
        unchecked {
            yieldAmount = _totalYieldPool * amountInREY / IREY(rey).totalSupply();
        }

        address user = msg.sender;
        IREY(rey).burn(user, amountInREY);
        IERC20(rETH).safeTransfer(user, yieldAmount);

        emit WithdrawYield(user, amountInREY, yieldAmount);

        return yieldAmount;
    }

    /**
     * @param nativeYield - Additional native yield amount
     */
    function updateYieldPool(uint256 nativeYield) external override onlyOutETHVault {
        unchecked {
            _totalYieldPool += nativeYield;
        }
    }

    /**
     * setter *
     */
    /**
     * @param minLockupDays_ - Min lockup days
     */
    function setMinLockupDays(uint16 minLockupDays_) external onlyOwner {
        _minLockupDays = minLockupDays_;
        emit SetMinLockupDays(minLockupDays_);
    }

    /**
     * @param maxLockupDays_ - Max lockup days
     */
    function setMaxLockupDays(uint16 maxLockupDays_) external onlyOwner {
        _maxLockupDays = maxLockupDays_;
        emit SetMaxLockupDays(maxLockupDays_);
    }

    /**
     * @param forceUnstakeFee_ - Force unstake fee
     */
    function setForceUnstakeFee(uint256 forceUnstakeFee_) external override onlyOwner {
        if (forceUnstakeFee_ > RATIO) {
            revert ForceUnstakeFeeOverflow();
        }

        _forceUnstakeFee = forceUnstakeFee_;
        emit SetForceUnstakeFee(forceUnstakeFee_);
    }

    /**
     * @param outETHVault_ - Address of outETHVault
     */
    function setOutETHVault(address outETHVault_) external override onlyOwner {
        _outETHVault = outETHVault_;
        emit SetOutETHVault(outETHVault_);
    }

    receive() external payable {}
}
