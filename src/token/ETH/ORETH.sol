// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IORETH.sol";
import "../../utils/Initializable.sol";
import "../../utils/IOutFlashCallee.sol";
import "../../blast/IBlastPoints.sol";
import "../../blast/GasManagerable.sol";
import "../../stake/interfaces/IStakeManager.sol";

/**
 * @title Outrun ETH
 */
contract ORETH is IORETH, ERC20, Initializable, ReentrancyGuard, Ownable, GasManagerable {
    uint256 public constant RATIO = 10000;
    uint256 public constant DAY_RATE_RATIO = 1e8;
    address private constant BLAST_POINTS = 0x2fc95838c71e76ec69ff817983BFf17c710F34E0; // TODO update mainnet blast points address

    address private _autoBot;
    address private _orETHStakeManager;
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
    ) ERC20("Outrun ETH", "orETH") Ownable(owner) GasManagerable(gasManager_) {
        setAutoBot(autoBot_);
        setRevenuePool(revenuePool_);
        setProtocolFeeRate(protocolFeeRate_);
        setFlashLoanFeeRate(flashLoanProviderFeeRate_, flashLoanProtocolFeeRate_);
        IBlastPoints(BLAST_POINTS).configurePointsOperator(pointsOperator);
    }

    function AutoBot() external view returns (address) {
        return _autoBot;
    }

    function ORETHStakeManager() external view returns (address) {
        return _orETHStakeManager;
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

    function setORETHStakeManager(address _stakeManager) public override onlyOwner {
        _orETHStakeManager = _stakeManager;
        emit SetORETHStakeManager(_stakeManager);
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
     * @param stakeManager_ - Address of orETHStakeManager
     */
    function initialize(address stakeManager_) external override initializer {
        BLAST.configureClaimableYield();
        setORETHStakeManager(stakeManager_);
    }

    /**
     * @dev Allows user to deposit ETH and mint orETH
     */
    function deposit() public payable override {
        uint256 amount = msg.value;
        require(amount != 0, ZeroInput());

        address msgSender = msg.sender;
        _mint(msgSender, amount);

        emit Deposit(msgSender, amount);
    }

    /**
     * @dev Allows user to withdraw ETH by orETH
     * @param amount - Amount of orETH for burn
     */
    function withdraw(uint256 amount) external override {
        require(amount != 0, ZeroInput());

        address msgSender = msg.sender;
        _burn(msgSender, amount);
        Address.sendValue(payable(msgSender), amount);

        emit Withdraw(msgSender, amount);
    }

    /**
     * @dev Accumulate ETH yield
     */
    function accumETHYield() public override returns (uint256 nativeYield, uint256 dayRate) {
        require(msg.sender == _autoBot, PermissionDenied());

        nativeYield = BLAST.claimAllYield(address(this), address(this));
        if (nativeYield > 0) {
            uint256 protocolFeeRate_ = _protocolFeeRate;
            if (protocolFeeRate_ > 0) {
                uint256 feeAmount;
                unchecked {
                    feeAmount = nativeYield * protocolFeeRate_ / RATIO;
                    nativeYield -= feeAmount;
                }

                Address.sendValue(payable(_revenuePool), feeAmount);
            }

            _mint(_orETHStakeManager, nativeYield);
            IStakeManager(_orETHStakeManager).accumYieldPool(nativeYield);

            unchecked {
                dayRate = nativeYield * DAY_RATE_RATIO / IStakeManager(_orETHStakeManager).totalStaked();
            }

            emit AccumETHYield(nativeYield, dayRate);
        }
    }

    /**
     * @dev Outrun ETH FlashLoan service
     * @param receiver - Address of receiver
     * @param amount - Amount of ETH loan
     * @param data - Additional data
     */
    function flashLoan(address payable receiver, uint256 amount, bytes calldata data) external override nonReentrant {
        require(amount != 0 && receiver != address(0), ZeroInput());

        uint256 balanceBefore = address(this).balance;
        (bool success, ) = receiver.call{value: amount}("");
        if (success) {
            IOutFlashCallee(receiver).onFlashLoan(msg.sender, amount, data);

            uint256 providerFeeAmount;
            uint256 protocolFeeAmount;
            unchecked {
                providerFeeAmount = amount * _flashLoanFeeRate.providerFeeRate / RATIO;
                protocolFeeAmount = amount * _flashLoanFeeRate.protocolFeeRate / RATIO;
                require(
                    address(this).balance >= balanceBefore + providerFeeAmount + protocolFeeAmount, 
                    FlashLoanRepayFailed()
                );
            }
            
            _mint(_orETHStakeManager, providerFeeAmount);
            IStakeManager(_orETHStakeManager).accumYieldPool(providerFeeAmount);
            Address.sendValue(payable(_revenuePool), protocolFeeAmount);

            emit FlashLoan(receiver, amount, providerFeeAmount, protocolFeeAmount);
        }
    }

    receive() external payable {
        deposit();
    }
}