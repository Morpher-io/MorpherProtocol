//SPDX-License-Identifier: GPLv3
pragma solidity ^0.8.15;

import {UUPSUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/ContextUpgradeable.sol";
import {PausableUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/PausableUpgradeable.sol";
import {EIP712Upgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {NoncesUpgradeable} from "../lib/openzeppelin-contracts-upgradable-5/contracts/utils/NoncesUpgradeable.sol";

import {IERC20} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts-5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "../lib/uniswap-v3-periphery/contracts/interfaces/external/IWETH9.sol";
import {IV3SwapRouter} from "../lib/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

import "./interfaces/IMorpherStateForAccessControl.sol";
import "./interfaces/IMorpherTradeEngine.sol"; // Changed from IMorpherTradeEngineExtended
import "./interfaces/IMorpherTokenMintable.sol";
import "./interfaces/IMorpherAccessControlConstants.sol";


contract MorpherReferralOracle is UUPSUpgradeable, ContextUpgradeable, PausableUpgradeable, EIP712Upgradeable, NoncesUpgradeable {
    using SafeERC20 for IMorpherTokenMintable;
    using SafeERC20 for IWETH9;

    struct CreateOrderStruct {
        bytes32 _marketId;
        uint256 _closeSharesAmount;
        uint256 _openMPHTokenAmount;
        bool _tradeDirection;
        uint256 _orderLeverage;
        uint256 _onlyIfPriceAbove;
        uint256 _onlyIfPriceBelow;
        uint256 _goodUntil;
        uint256 _goodFrom;
    }

    struct StoredReferralOpenInfo {
        address beneficiary;
        uint256 initialInvestmentValue;
    }

    IMorpherStateForAccessControl public morpherState; // For AccessControl address and potentially market active checks
    address public morpherTradeEngineAddress;
    address public morpherTokenAddress;

    address public wethAddress; // WETH address on Base
    address public uniswapRouter;
    uint24 public constant POOL_FEE = 3000; // Default Uniswap V3 pool fee

    uint256 public referralPercentage; // e.g., 1000 for 10.00% (value * 1000 / REFERRAL_PERCENTAGE_PRECISION)
    uint256 public constant REFERRAL_PERCENTAGE_PRECISION = 10000;

    mapping(bytes32 => address) public pendingOrderToBeneficiary; // Maps orderId to beneficiary before MTE processing
    mapping(address => mapping(bytes32 => StoredReferralOpenInfo)) public activeReferrals;

    // Roles (can be fetched from AccessControl or defined if static and known)
    // For simplicity here, using local constants, assuming they match MorpherAccessControl
    bytes32 public constant ADMINISTRATOR_ROLE = keccak256("ADMINISTRATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    // PROXYUPDATER_ROLE will be fetched from AccessControl in _authorizeUpgrade

    event ReferralOrderCreated(
        bytes32 indexed orderId,
        address indexed trader,
        address indexed beneficiary,
        bytes32 marketId, // Removed indexed
        uint256 openMPHTokenAmount,
        bool tradeDirection,
        uint256 orderLeverage
    );

    event ReferralAdminSet(address indexed admin, address indexed targetAddress, string setting, uint256 value);
    event ReferralAdminAddressSet(address indexed admin, address indexed targetAddress, string setting, address value);
    event ReferralOpenDetailsStored(address indexed trader, bytes32 indexed marketId, address indexed beneficiary, uint256 initialInvestmentValue);
    event ReferralBonusPaid(address indexed trader, bytes32 indexed marketId, address indexed beneficiary, uint256 lossAmount, uint256 bonusAmount);


    function initialize(
        address _morpherStateAddress,
        address _morpherTradeEngineAddress,
        address _morpherTokenAddress,
        address _wethAddress,
        address _uniswapRouterAddress,
        uint256 _initialReferralPercentage,
        string memory _eip712Name,
        string memory _eip712Version
    ) public initializer {
        __UUPSUpgradeable_init();
        __Context_init();
        __Pausable_init();
        __EIP712_init(_eip712Name, _eip712Version);
        __Nonces_init();

        morpherState = IMorpherStateForAccessControl(_morpherStateAddress);
        morpherTradeEngineAddress = _morpherTradeEngineAddress;
        morpherTokenAddress = _morpherTokenAddress;
        wethAddress = _wethAddress;
        uniswapRouter = _uniswapRouterAddress;
        referralPercentage = _initialReferralPercentage;

        emit ReferralAdminAddressSet(msg.sender, _morpherStateAddress, "MorpherStateAddress", _morpherStateAddress);
        emit ReferralAdminAddressSet(msg.sender, _morpherTradeEngineAddress, "MorpherTradeEngineAddress", _morpherTradeEngineAddress);
        emit ReferralAdminAddressSet(msg.sender, _morpherTokenAddress, "MorpherTokenAddress", _morpherTokenAddress);
        emit ReferralAdminAddressSet(msg.sender, _wethAddress, "WethAddress", _wethAddress);
        emit ReferralAdminAddressSet(msg.sender, _uniswapRouterAddress, "UniswapRouter", _uniswapRouterAddress);
        emit ReferralAdminSet(msg.sender, address(this), "ReferralPercentage", _initialReferralPercentage);
    }

    function _authorizeUpgrade(address newImplementation) internal override virtual {
        address accessControlAddress = morpherState.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "MRO: AccessControl not set in State");
        IMorpherAccessControlConstants ac = IMorpherAccessControlConstants(accessControlAddress);
        require(ac.hasRole(ac.PROXYUPDATER_ROLE(), _msgSender()), "MRO: Caller is not the proxy updater");
    }

    modifier onlyRole(bytes32 role) {
        address accessControlAddress = morpherState.morpherAccessControlAddress();
        require(accessControlAddress != address(0), "MRO: AccessControl not set in State");
        require(IMorpherAccessControlConstants(accessControlAddress).hasRole(role, _msgSender()), "MRO: Permission denied.");
        _;
    }

    function createOrder(
        CreateOrderStruct memory createOrderParams,
        address beneficiaryAddress
    ) public payable virtual whenNotPaused returns (bytes32 orderId) {
        require(beneficiaryAddress != address(0), "MRO: Beneficiary address cannot be zero");
        require(beneficiaryAddress != _msgSender(), "MRO: Beneficiary cannot be trader");

        // Gas for callback logic removed

        // Call standard requestOrderId on MorpherTradeEngine
        orderId = IMorpherTradeEngine(morpherTradeEngineAddress).requestOrderId(
            _msgSender(),
            createOrderParams._marketId,
            createOrderParams._closeSharesAmount,
            createOrderParams._openMPHTokenAmount,
            createOrderParams._tradeDirection,
            createOrderParams._orderLeverage
        );

        pendingOrderToBeneficiary[orderId] = beneficiaryAddress;
        IMorpherTradeEngine(morpherTradeEngineAddress).markOrderAsReferred(orderId); // Changed type cast
        
        // The MTE will call recordReferralOpen upon successful opening.
        // Here we emit an event that the referral order process has started.
        emit ReferralOrderCreated(
            orderId,
            _msgSender(),
            beneficiaryAddress,
            createOrderParams._marketId,
            createOrderParams._openMPHTokenAmount,
            createOrderParams._tradeDirection,
            createOrderParams._orderLeverage
        );
        return orderId;
    }

    function createOrderFromGasToken(
        CreateOrderStruct memory createOrderParams,
        address beneficiaryAddress
    ) public payable virtual whenNotPaused returns (bytes32 orderId) {
        require(beneficiaryAddress != address(0), "MRO: Beneficiary address cannot be zero");
        require(beneficiaryAddress != _msgSender(), "MRO: Beneficiary cannot be trader");
        require(msg.value > 0, "MRO: Must send ETH to swap");
        require(wethAddress != address(0), "MRO: WETH address not set");
        require(uniswapRouter != address(0), "MRO: Uniswap router not set");
        require(morpherTokenAddress != address(0), "MRO: Morpher token address not set");

        // Gas for callback logic removed
        uint256 ethForSwap = msg.value;
        
        IWETH9(wethAddress).deposit{value: ethForSwap}();
        
        // Use SafeERC20.safeApprove by casting wethAddress to IERC20
        // or ensure IWETH9 is compatible with SafeERC20 usage.
        // Standard WETH `approve` is also an option.
        // Given `using SafeERC20 for IWETH9;` let's use it correctly.
        IERC20(wethAddress).approve(uniswapRouter, ethForSwap);
        
        bytes memory path = abi.encodePacked(
            wethAddress,
            POOL_FEE,
            morpherTokenAddress
        );
        
        IV3SwapRouter.ExactInputParams memory swapParams = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(this), // Swap to this contract first
            // deadline: block.timestamp, // Using block.timestamp as deadline
            amountIn: ethForSwap,
            amountOutMinimum: createOrderParams._openMPHTokenAmount // User specifies min MPH out
        });
        
        uint256 mphReceived = IV3SwapRouter(uniswapRouter).exactInput(swapParams);
        require(mphReceived >= createOrderParams._openMPHTokenAmount, "MRO: Swap returned less than minimum");

        // Update openMPHTokenAmount to actual received amount for the order
        CreateOrderStruct memory finalOrderParams = createOrderParams;
        finalOrderParams._openMPHTokenAmount = mphReceived;

        // Temporarily grant allowance to Trade Engine for the received MPH tokens
        // The Trade Engine will pull these tokens when processing the order via its escrow mechanism or direct burn.
        IMorpherTokenMintable(morpherTokenAddress).approve(morpherTradeEngineAddress, mphReceived);
        
        orderId = IMorpherTradeEngine(morpherTradeEngineAddress).requestOrderId(
            _msgSender(), // The original user is the trader
            finalOrderParams._marketId,
            finalOrderParams._closeSharesAmount,
            finalOrderParams._openMPHTokenAmount,
            finalOrderParams._tradeDirection,
            finalOrderParams._orderLeverage
        );

        pendingOrderToBeneficiary[orderId] = beneficiaryAddress;
        IMorpherTradeEngine(morpherTradeEngineAddress).markOrderAsReferred(orderId); // Changed type cast

        // Revoke allowance after MTE interaction is expected to be complete (or MTE should handle it)
        // For safety, could be done by MTE callback, or assume MTE consumes it.
        // If MTE doesn't consume all (e.g. partial open), this needs more robust handling.
        // For now, let's assume MTE consumes what it needs.
        // IMorpherTokenMintable(morpherTokenAddress).safeApprove(morpherTradeEngineAddress, 0);


        emit ReferralOrderCreated(
            orderId,
            _msgSender(),
            beneficiaryAddress,
            finalOrderParams._marketId,
            finalOrderParams._openMPHTokenAmount,
            finalOrderParams._tradeDirection,
            finalOrderParams._orderLeverage
        );
        return orderId;
    }

    // --- Referral Data Management (called by MorpherTradeEngine) ---

    function recordReferralOpen(
        bytes32 orderId,
        address traderAddress,
        bytes32 marketId,
        uint256 initialInvestmentValue
    ) external virtual whenNotPaused {
        require(msg.sender == morpherTradeEngineAddress, "MRO: Caller must be MorpherTradeEngine");
        address beneficiary = pendingOrderToBeneficiary[orderId];
        require(beneficiary != address(0), "MRO: No pending beneficiary for orderId");

        activeReferrals[traderAddress][marketId] = StoredReferralOpenInfo(beneficiary, initialInvestmentValue);
        delete pendingOrderToBeneficiary[orderId]; // Clean up pending entry
        emit ReferralOpenDetailsStored(traderAddress, marketId, beneficiary, initialInvestmentValue);
    }

    function processReferralClose(
        address traderAddress,
        bytes32 marketId,
        uint256 finalPayoutValue // Amount trader received upon closing
    ) external virtual whenNotPaused {
        require(msg.sender == morpherTradeEngineAddress, "MRO: Caller must be MorpherTradeEngine");
        require(morpherTokenAddress != address(0), "MRO: Morpher token address not set");

        StoredReferralOpenInfo storage referralInfo = activeReferrals[traderAddress][marketId];
        require(referralInfo.beneficiary != address(0), "MRO: No active referral found or already processed");

        uint256 initialInvestment = referralInfo.initialInvestmentValue;
        address beneficiary = referralInfo.beneficiary;

        if (finalPayoutValue < initialInvestment) {
            uint256 lossAmount = initialInvestment - finalPayoutValue;
            if (lossAmount > 0 && referralPercentage > 0) {
                uint256 bonusAmount = (lossAmount * referralPercentage) / REFERRAL_PERCENTAGE_PRECISION;
                if (bonusAmount > 0) {
                    IMorpherTokenMintable(morpherTokenAddress).mint(beneficiary, bonusAmount);
                    emit ReferralBonusPaid(traderAddress, marketId, beneficiary, lossAmount, bonusAmount);
                }
            }
        }

        // Clear the referral info after processing
        delete activeReferrals[traderAddress][marketId];
    }

    // --- Admin Functions ---
    function setMorpherStateAddress(address _newAddress) external virtual onlyRole(ADMINISTRATOR_ROLE) {
        morpherState = IMorpherStateForAccessControl(_newAddress);
        emit ReferralAdminAddressSet(_msgSender(), _newAddress, "MorpherStateAddress", _newAddress);
    }

    function setMorpherTradeEngineAddress(address _newAddress) external virtual onlyRole(ADMINISTRATOR_ROLE) {
        morpherTradeEngineAddress = _newAddress;
        emit ReferralAdminAddressSet(_msgSender(), _newAddress, "MorpherTradeEngineAddress", _newAddress);
    }

    function setMorpherTokenAddress(address _newAddress) external virtual onlyRole(ADMINISTRATOR_ROLE) {
        morpherTokenAddress = _newAddress;
        emit ReferralAdminAddressSet(_msgSender(), _newAddress, "MorpherTokenAddress", _newAddress);
    }

    function setWethAddress(address _newAddress) external virtual onlyRole(ADMINISTRATOR_ROLE) {
        wethAddress = _newAddress;
        emit ReferralAdminAddressSet(_msgSender(), _newAddress, "WethAddress", _newAddress);
    }

    function setUniswapRouterAddress(address _newAddress) external virtual onlyRole(ADMINISTRATOR_ROLE) {
        uniswapRouter = _newAddress;
        emit ReferralAdminAddressSet(_msgSender(), _newAddress, "UniswapRouter", _newAddress);
    }

    function setReferralPercentage(uint256 _newPercentage) external virtual onlyRole(ADMINISTRATOR_ROLE) {
        require(_newPercentage <= REFERRAL_PERCENTAGE_PRECISION, "MRO: Percentage too high"); // Max 100%
        referralPercentage = _newPercentage;
        emit ReferralAdminSet(_msgSender(), address(this), "ReferralPercentage", _newPercentage);
    }
    
    function pause() public virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // --- Fallback and Receive ---
    receive() external payable {
        // Can be used to fund contract for gas or other purposes if needed
    }
}
