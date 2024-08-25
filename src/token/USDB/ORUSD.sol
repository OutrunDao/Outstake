// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IORUSD.sol";
import "../../utils/Initializable.sol";
import "../../utils/IOutFlashCallee.sol";
import "../../blast/IBlastPoints.sol";
import "../../blast/GasManagerable.sol";
import "../../blast/IERC20Rebasing.sol";
import "../../stake/interfaces/IORUSDStakeManager.sol";

/**
 * @title Outrun USDB
 */
contract ORUSD is IORUSD, ERC20, Initializable, ReentrancyGuard, Ownable, GasManagerable, BlastModeEnum {
    using SafeERC20 for IERC20;

    address public constant USDB = 0x4200000000000000000000000000000000000022;
    uint256 public constant RATIO = 10000;
    uint256 public constant DAY_RATE_RATIO = 1e8;
    address private constant BLAST_POINTS = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0; // TODO update mainnet blast points address

    address private _autoBot;
    address private _orUSDStakeManager;
    address private _revenuePool;
    uint256 private _protocolFeeRate;
    FlashLoanFeeRate private _flashLoanFeeRate;

    /**
     * @param owner - Address of owner
     * @param gasManager_ - Address of gas manager
     * @param autoBot_ - Address of autoBot
     * @param revenuePool_ - Address of revenue pool
     * @param protocolFeeRate_ - Protocol fee rate
     * @param flashLoanProviderFeeRate_ - Flashloan provider fee rate
     * @param flashLoanProtocolFeeRate_ - Flashloan protocol fee rate
     */
    constructor(
        address owner, 
        address gasManager_,
        address autoBot_,
        address revenuePool_, 
        address pointsOperator, 
        uint256 protocolFeeRate_, 
        uint128 flashLoanProviderFeeRate_, 
        uint128 flashLoanProtocolFeeRate_
    ) ERC20("Outrun USDB", "orUSD") Ownable(owner) GasManagerable(gasManager_) {
        setAutoBot(autoBot_);
        setRevenuePool(revenuePool_);
        setProtocolFeeRate(protocolFeeRate_);
        setFlashLoanFeeRate(flashLoanProviderFeeRate_, flashLoanProtocolFeeRate_);
        IBlastPoints(BLAST_POINTS).configurePointsOperator(pointsOperator);
    }

    function AutoBot() external view returns (address) {
        return _autoBot;
    }
    
    function ORUSDStakeManager() external view returns (address) {
        return _orUSDStakeManager;
    }

    function revenuePool() external view returns (address) {
        return _revenuePool;
    }

    function protocolFeeRate() external view returns (uint256) {
        return _protocolFeeRate;
    }

    function flashLoanFeeRate() external view returns (FlashLoanFeeRate memory) {
        return _flashLoanFeeRate;
    }


    function setAutoBot(address _bot) public override onlyOwner {
        _autoBot = _bot;
        emit SetAutoBot(_bot);
    }

    function setORUSDStakeManager(address _stakeManager) public override onlyOwner {
        _orUSDStakeManager = _stakeManager;
        emit SetORUSDStakeManager(_stakeManager);
    }

    function setRevenuePool(address _pool) public override onlyOwner {
        _revenuePool = _pool;
        emit SetRevenuePool(_pool);
    }

    function setProtocolFeeRate(uint256 protocolFeeRate_) public override onlyOwner {
        require(protocolFeeRate_ <= RATIO, FeeRateOverflow());

        _protocolFeeRate = protocolFeeRate_;
        emit SetProtocolFeeRate(protocolFeeRate_);
    }

    function setFlashLoanFeeRate(uint128 providerFeeRate_, uint128 protocolFeeRate_) public override onlyOwner {
        require(providerFeeRate_ + protocolFeeRate_ <= RATIO, FeeRateOverflow());

        _flashLoanFeeRate = FlashLoanFeeRate(providerFeeRate_, protocolFeeRate_);
        emit SetFlashLoanFeeRate(providerFeeRate_, protocolFeeRate_);
    }

    /**
     * @dev Initializer
     * @param stakeManager_ - Address of orUSDStakeManager
     */
    function initialize(address stakeManager_) external override initializer {
        IERC20Rebasing(USDB).configure(YieldMode.CLAIMABLE);
        setORUSDStakeManager(stakeManager_);
    }

    /**
     * @dev Allows user to deposit USDB and mint orUSD
     * @notice User must have approved this contract to spend USDB
     */
    function deposit(uint256 amount) external override {
        require(amount != 0, ZeroInput());

        address msgSender = msg.sender;
        IERC20(USDB).safeTransferFrom(msgSender, address(this), amount);
        _mint(msgSender, amount);

        emit Deposit(msgSender, amount);
    }

    /**
     * @dev Allows user to withdraw USDB by orUSD
     * @param amount - Amount of orUSD for burn
     */
    function withdraw(uint256 amount) external override {
        require(amount != 0, ZeroInput());

        address msgSender = msg.sender;
        _burn(msgSender, amount);
        IERC20(USDB).safeTransfer(msgSender, amount);

        emit Withdraw(msgSender, amount);
    }

    /**
     * @dev Accumulate USDB yield
     */
    function accumUSDBYield() public override returns (uint256 realYield, uint256 dayRate) {
        require(msg.sender == _autoBot, PermissionDenied());

        uint256 nativeYield = IERC20Rebasing(USDB).getClaimableAmount(address(this));
        if (nativeYield > 0) {
            IERC20Rebasing(USDB).claim(_orUSDStakeManager, nativeYield);
            realYield = IORUSDStakeManager(_orUSDStakeManager).handleUSDBYield(_protocolFeeRate, _revenuePool);
            _mint(_orUSDStakeManager, realYield);

            unchecked {
                dayRate = realYield * DAY_RATE_RATIO / IORUSDStakeManager(_orUSDStakeManager).totalStaked();
            }

            emit AccumUSDBYield(realYield, dayRate);
        }
    }

     /**
     * @dev Outrun USDB FlashLoan service
     * @param receiver - Address of receiver
     * @param amount - Amount of USDB loan
     * @param data - Additional data
     */
    function flashLoan(address receiver, uint256 amount, bytes calldata data) external override nonReentrant {
        require(amount != 0 && receiver != address(0), ZeroInput());

        uint256 balanceBefore = IERC20(USDB).balanceOf(address(this));
        IERC20(USDB).safeTransfer(receiver, amount);
        IOutFlashCallee(receiver).onFlashLoan(msg.sender, amount, data);

        uint256 providerFeeAmount;
        uint256 protocolFeeAmount;
        unchecked {
            providerFeeAmount = amount * _flashLoanFeeRate.providerFeeRate / RATIO;
            protocolFeeAmount = amount * _flashLoanFeeRate.protocolFeeRate / RATIO;
            require(
                IERC20(USDB).balanceOf(address(this)) >= balanceBefore + providerFeeAmount + protocolFeeAmount, 
                FlashLoanRepayFailed() 
            );
        }
        
        _mint(_orUSDStakeManager, providerFeeAmount);
        IORUSDStakeManager(_orUSDStakeManager).accumYieldPool(providerFeeAmount);
        IERC20(USDB).safeTransfer(_revenuePool, protocolFeeAmount);

        emit FlashLoan(receiver, amount, providerFeeAmount, protocolFeeAmount);
    }
}