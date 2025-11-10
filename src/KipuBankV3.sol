// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    AggregatorV3Interface
} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IUniswapV2Router02
} from "v2-periphery/interfaces/IUniswapV2Router02.sol";

/**
 * @title KipuBankV3
 * @author @aetche
 * @notice A multi-token vault that swaps all deposits (ETH & ERC20s) into USDC.
 * @dev All internal accounting is done in USDC.
 */

contract KipuBankV3 is Pausable, AccessControl {
    using SafeERC20 for IERC20;

    /// @notice Total number of withdrawals executed.
    uint256 public withdrawalCount;

    /// @notice Total number of deposits executed.
    uint256 public depositCount;

    /// @notice The total amount of USDC held by this contract.
    uint256 public totalBalanceUsdc;

    /// @notice Maximum USDC withdrawal allowed per transaction.
    uint256 public immutable WITHDRAWAL_LIMIT;

    /// @notice Global cap of USDC this contract can hold.
    uint256 public immutable BANK_CAP_USD;

    /// @notice Mapping from user address => user's USDC balance.
    mapping(address user => uint256 userBalance) public vault;

    /// @notice Constant for native ETH.
    address public constant ETH_ADDRESS = address(0);

    /// @notice Uniswap V2 Router for token swaps.
    IUniswapV2Router02 public immutable ROUTER;

    /// @notice Address of the USDC token contract.
    address public immutable USDC;

    /// @notice Address of the WETH token contract.
    address public immutable WETH;

    /**
     * @notice Configuration data for a supported token's price feed.
     * @param dataFeed The Chainlink AggregatorV3Interface instance.
     * @param tokenDecimals The decimal precision of the token (e.g., 18 for ETH).
     * @param dataFeedDecimals The decimal precision of the price feed (e.g., 8 for USD pairs).
     */
    struct DataFeed {
        AggregatorV3Interface dataFeed;
        uint8 tokenDecimals;
        uint8 dataFeedDecimals;
    }

    /// @notice Mapping from a token address to its price feed configuration.
    mapping(address tokenAddress => DataFeed dataFeed) public dataFeeds;

    /// @notice Role identifier for admin tasks.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Internal flag for reentrancy attacks (1 = Not Entered, 2 = Entered).
    uint8 private flag;

    // ========= EVENTS =========

    /// @notice Emitted when a deposit is successfully received.
    /// @param sender The address that made the deposit.
    /// @param token The address of the deposited token (address(0) for ETH).
    /// @param amount The amount of tokens (or wei) deposited.
    event Deposit(address sender, address token, uint256 amount);

    /// @notice Emitted when a withdrawal is successfully executed.
    /// @param owner The address of the user withdrawing funds.
    /// @param amount The amount of USDC withdrawn.
    event Withdrawal(address owner, uint256 amount);

    /// @notice Emitted when a new price feed is set by an admin.
    /// @param addr The address of the price feed contract.
    /// @param time The block timestamp of the event.
    event FeedSet(address indexed addr, uint256 time);
    // ========= ERRORS =========

    /// @notice Thrown when a deposit would exceed the global bank cap.
    /// @param totalBalance The current total USDC balance of the contract.
    error BankCapReached(uint256 totalBalance);

    /// @notice Thrown when an invalid amount is provided (e.g., insufficient funds).
    /// @param amount The amount that caused the error.
    error InvalidAmount(uint amount);

    /// @notice Thrown when a transaction amount is zero.
    error ZeroAmount();

    /// @notice Thrown when a zero address is provided where not allowed.
    error ZeroAddress();

    /// @notice Thrown by the constructor for invalid setup parameters.
    error InvalidContract();

    /// @notice Thrown when a reentrancy attempt is detected.
    /// @param caller The address that triggered the reentrancy guard.
    error Forbidden(address caller);

    // ========= CONSTRUCTOR =========

    /**
     * @notice Initializes the contract, setting roles, Uniswap/USDC addresses and ETH price feed.
     * @param _ethOracle The Chainlink ETH/USD price feed address.
     * @param _router The address of the Uniswap V2 Router.
     * @param _usdc The address of the USDC token.
     * @param _withdrawalLimit The max withdrawal per tx (in USDC, 6 decimals).
     * @param _bankCap The global deposit cap (in USDC, 6 decimals).
     * @param _initialOwner The address to be granted ADMIN_ROLE.
     */
    constructor(
        AggregatorV3Interface _ethOracle,
        address _router,
        address _usdc,
        uint256 _withdrawalLimit,
        uint256 _bankCap,
        address _initialOwner
    ) {
        if (_ethOracle == AggregatorV3Interface(ETH_ADDRESS))
            revert InvalidContract();

        if (_router == ETH_ADDRESS || _usdc == ETH_ADDRESS)
            revert ZeroAddress();
        ROUTER = IUniswapV2Router02(_router);
        USDC = _usdc;
        WETH = ROUTER.WETH();

        _grantRole(ADMIN_ROLE, _initialOwner);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        dataFeeds[ETH_ADDRESS] = DataFeed({
            dataFeed: _ethOracle,
            tokenDecimals: 18,
            dataFeedDecimals: _ethOracle.decimals()
        });
        flag = 1;
        emit FeedSet(address(_ethOracle), block.timestamp);
        WITHDRAWAL_LIMIT = _withdrawalLimit;
        BANK_CAP_USD = _bankCap;
    }

    // ========= MODIFIERS =========

    /// @notice Protects a function from reentrancy attacks.
    modifier reentrancyGuard() {
        if (flag != 1) revert Forbidden(msg.sender);
        flag = 2;
        _;
        flag = 1;
    }

    /**
     * @notice Checks if the user has sufficient USDC balance for a withdrawal.
     * @param amount USDC amount to withdraw.
     */
    modifier validWithdrawalAmount(uint256 amount) {
        if (vault[msg.sender] < amount) revert InvalidAmount(amount);
        _;
    }

    /// @notice Reverts if the provided amount is zero.
    /// @param amount The amount to check.
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    // ========= FUNCTIONS =========

    /**
     * @notice [ADMIN] Adds a new ERC20 token and its price feed to the bank.
     * @param tokenAddress The address of the ERC20 token contract.
     * @param feed The address of the token's Chainlink price feed.
     * @dev Makes external calls to fetch decimals from the token and feed.
     */

    function setFeeds(
        address tokenAddress,
        AggregatorV3Interface feed
    ) external onlyRole(ADMIN_ROLE) {
        address _addressFeed = address(feed);
        dataFeeds[tokenAddress] = DataFeed({
            dataFeed: feed,
            tokenDecimals: IERC20Metadata(tokenAddress).decimals(),
            dataFeedDecimals: feed.decimals()
        });

        emit FeedSet(_addressFeed, block.timestamp);
    }

    /**
     * @notice Deposits native ETH, swaps it to USDC, and credits the user.
     * @param amountOutMin The minimum amount of USDC to receive from the swap.
     */
    function depositEth(
        uint256 amountOutMin
    ) external payable whenNotPaused reentrancyGuard nonZeroAmount(msg.value) {
        uint256 _amountUsdc = _swapEthToUsdc(msg.value, amountOutMin);

        uint256 _newTotalBalanceUsdc = totalBalanceUsdc + _amountUsdc;

        if (_newTotalBalanceUsdc > BANK_CAP_USD)
            revert BankCapReached(_newTotalBalanceUsdc);

        emit Deposit(msg.sender, ETH_ADDRESS, msg.value);

        unchecked {
            totalBalanceUsdc = _newTotalBalanceUsdc;
            vault[msg.sender] += _amountUsdc;
        }

        _setDepositCount();
    }

    /**
     * @notice Deposits an ERC20 token, swaps it to USDC, and credits the user.
     * @param token The address of the ERC20 token to deposit.
     * @param amount The raw amount of the ERC20 token to deposit.
     * @param amountOutMin The minimum amount of USDC to receive from the swap.
     */
    function depositToken(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external whenNotPaused reentrancyGuard nonZeroAmount(amount) {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 _amountUsdc = _swapTokenToUsdc(token, amount, amountOutMin);

        uint256 _newTotalBalanceUsdc = totalBalanceUsdc + _amountUsdc;

        if (_newTotalBalanceUsdc > BANK_CAP_USD)
            revert BankCapReached(_newTotalBalanceUsdc);

        emit Deposit(msg.sender, token, amount);

        unchecked {
            totalBalanceUsdc = _newTotalBalanceUsdc;
            vault[msg.sender] += _amountUsdc;
        }
        _setDepositCount();
    }

    /**
     * @notice Allows users to withdraw their USDC balance.
     * @param amount The amount of USDC to withdraw.
     */
    function withdrawUsdc(
        uint256 amount
    ) external whenNotPaused reentrancyGuard validWithdrawalAmount(amount) {
        emit Withdrawal(msg.sender, amount);
        if (amount > WITHDRAWAL_LIMIT) revert InvalidAmount(amount);

        unchecked {
            vault[msg.sender] -= amount;
            totalBalanceUsdc -= amount;
        }
        _setWithdrawalCount();
        IERC20(USDC).safeTransfer(msg.sender, amount);
    }

    // ========= INTERNAL & VIEW FUNCTIONS =========

    /// @notice Increments the global withdrawal counter.
    function _setWithdrawalCount() private {
        withdrawalCount += 1;
    }

    /// @notice Increments the global deposit counter.
    function _setDepositCount() private {
        depositCount += 1;
    }

    /**
     * @notice Gets a user's total USDC balance.
     * @param account The address of the user.
     * @return _usdcTotal The total USDC value.
     */
    function getUserBalance(
        address account
    ) external view returns (uint256 _usdcTotal) {
        return vault[account];
    }

    /**
     * @notice Gets the latest price of a token from its data feed.
     * @param token The address of the token.
     * @return _latestAnswer The latest price of the token.
     */
    function getTokenPrice(
        address token
    ) public view returns (int256 _latestAnswer) {
        (, _latestAnswer, , , ) = dataFeeds[token].dataFeed.latestRoundData();

        return _latestAnswer;
    }

    function getEthPrice() external view returns (int256 _latestAnswer) {
        return getTokenPrice(ETH_ADDRESS);
    }

    /**
     * @notice Internal function to swap tokens to USDC via Uniswap V2.
     * @param amountIn The amount of the input token to swap.
     * @param amountOutMin The minimum acceptable amount of USDC to receive.
     * @return _amount The amount of USDC received from the swap.
     */
    function _swapTokenToUsdc(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin
    ) private returns (uint256 _amount) {
        if (tokenIn == ETH_ADDRESS) _swapEthToUsdc(amountIn, amountOutMin);

        if (tokenIn == USDC) {
            return amountIn;
        }

        if (
            IERC20(tokenIn).allowance(address(this), address(ROUTER)) < amountIn
        ) {
            IERC20(tokenIn).safeIncreaseAllowance(
                address(ROUTER),
                type(uint256).max
            );
        }

        address[] memory path;
        if (tokenIn == WETH) {
            path = new address[](2);
            path[0] = WETH;
            path[1] = USDC;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WETH;
            path[2] = USDC;
        }

        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Internal function to swap native ETH for USDC.
     * @param amountIn The amount of wei to swap.
     * @param amountOutMin The minimum acceptable amount of USDC to receive.
     * @return _amount The amount of USDC received from the swap.
     */
    function _swapEthToUsdc(
        uint256 amountIn,
        uint256 amountOutMin
    ) private returns (uint256 _amount) {
        if (amountIn == 0 || amountOutMin == 0) revert ZeroAmount();

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        uint256[] memory amounts = ROUTER.swapExactETHForTokens{
            value: amountIn
        }(amountOutMin, path, address(this), block.timestamp);

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Previews the amount of USDC received from depositing a token.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of the input token to deposit.
     * @return amountOut The estimated amount of USDC to be received.
     */
    function previewDeposit(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();

        if (tokenIn == USDC) {
            return amountIn;
        }

        address[] memory path;
        if (tokenIn == WETH || tokenIn == ETH_ADDRESS) {
            path = new address[](2);
            path[0] = WETH;
            path[1] = USDC;
        } else {
            path = new address[](3);
            path[0] = tokenIn;
            path[1] = WETH;
            path[2] = USDC;
        }

        uint256[] memory amounts = ROUTER.getAmountsOut(amountIn, path);
        return amounts[amounts.length - 1];
    }

    /// @notice [ADMIN] Pauses all contract functions guarded by `whenNotPaused`.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice [ADMIN] Unpauses the contract.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
