// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@equalizerfinance/flashloan-contracts/contracts/interfaces/IFlashLoanReceiver.sol";
import "@equalizerfinance/flashloan-contracts/contracts/interfaces/IFlashLoan.sol";

contract FlashLoanProvider is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    address public constant WETH_ADDRESS = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    address public constant USDC_ADDRESS = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant DAI_ADDRESS = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public constant UNI_V3_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNI_V3_FACTORY_ADDRESS = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    IFlashLoan public constant flashLoan = IFlashLoan(0x0d4A11d5EEaaC28EC3F61d100daF4d40471f1852);
    ISwapRouter public constant swapRouter = ISwapRouter(UNI_V3_ROUTER_ADDRESS);

    function startFlashLoan() external {
        address[] memory assets = new address[](1);
        assets[0] = USDC_ADDRESS;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000000; // 1 USDC
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0; // no debt limit
        address receiverAddress = address(this);
        bytes memory params = abi.encodeWithSignature("executeOperation()");
        flashLoan.flashLoan(receiverAddress, assets, amounts, modes, address(this), params, 0);
    }

    function executeOperation() external {
        // Step 1: Add liquidity to Uniswap V3
        IUniswapV3Pool pool = IUniswapV3Pool(UNI_V3_FACTORY_ADDRESS.getPool(WETH_ADDRESS, USDC_ADDRESS, 3000));
        require(address(pool) != address(0), "POOL_NOT_FOUND");
        uint256 amount0Desired = 1 ether;
        uint256 amount1Desired = 1000000;
        uint2560Min = 0;
        uint256 amount1Min = 0;
        uint24 fee = 3000;
        uint160 sqrtPriceLimitX96 = 0;
        IERC20(WETH_ADDRESS).safeApprove(UNI_V3_ROUTER_ADDRESS, amount0Desired);
        IERC20(USDC_ADDRESS).safeApprove(UNI_V3_ROUTER_ADDRESS, amount1Desired);
        (uint256 amount0, uint256 amount1, uint256 liquidity) = swapRouter.addLiquidity(
            WETH_ADDRESS,
            USDC_ADDRESS,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            address(this),
            block.timestamp + 1 hours
        );
        require(amount0 >= amount0Min, "INSUFFICIENT_AMOUNT0");
        require(amount1 >= amount1Min, "INSUFFICIENT_AMOUNT1");

        // Step 2: Swap  tokens in Uniswap V3
        uint256 amountIn = 1 ether;
        uint256 amountOutMin = 1000000;
        uint160 sqrtPriceLimitX96Swap = 0;
        bytes memory path = abi.encodePacked(WETH_ADDRESS, USDC_ADDRESS);
        IERC20(WETH_ADDRESS).safeApprove(UNI_V3_ROUTER_ADDRESS, amountIn);
        swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH_ADDRESS,
                tokenOut: USDC_ADDRESS,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp + 1 hours,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: sqrtPriceLimitX96Swap
            })
        );

        // Step 3: Remove liquidity from Uniswap V3
        uint128 liquidityToRemove = uint128(liquidity);
        uint256 amount0MinRemove = 0;
        uint256 amount1MinRemove = 0;
        IERC20(pool.token0()).safeApprove(UNI_V3_ROUTER_ADDRESS, liquidityToRemove);
        IERC20(pool.token1()).safeApprove(UNI_V3_ROUTER_ADDRESS, liquidityToRemove);
        (uint256 amount0Remove, uint256 amount1Remove) = swapRouter.removeLiquidity(
            WETH_ADDRESS,
            USDC_ADDRESS,
            liquidityToRemove,
            amount0MinRemove,
            amount1MinRemove,
            address(this),
            block.timestamp + 1 hours
        );
        require(amount0Remove >= amount0MinRemove, "INSUFFICIENT_AMOUNT0");
        require(amount1Remove >= amount1MinRemove, "INSUFFICIENT_AMOUNT1");

        // Step 4: Pay back the flashloan
        IERC20(USDC_ADDRESS).safeApprove(address(flashLoan), 1000000);
        flashLoan.repay(USDC_ADDRESS, 1000000);

        // Step 5: Transfer any remaining tokens back to the sender
        IERC20(WETH_ADDRESS).safeTransfer(msg.sender, IERC20(WETH_ADDRESS).balanceOf(address(this)));
        IERC20(USDC_ADDRESS).safeTransfer(msg.sender, IERC20(USDC_ADDRESS).balanceOf(address(this)));
    }

    function onFlashLoan(
        address _initiator,
        address[] calldata _assets,
        uint256[] calldata _amounts,
        uint256[] calldata _premiums,
        address _originator,
        bytes calldata _params
    ) external override returns (bytes32) {
        require(_assets.length == 1, "INVALID_ASSETS_LENGTH");
        require(_amounts.length == 1, "INVALID_AMOUNTS_LENGTH");
        require(_premiums.length == 1, "INVALID_PREMIUMS_LENGTH");
        require(_assets[0] == USDC_ADDRESS, "INVALID_ASSET");
        require(_amounts[0] == 1000000, "INVALID_AMOUNT");
        require(_premiums[0] == 0, "INVALID_PREMIUM");
        require(_originator == address(this), "INVALID_ORIGINATOR");
        require(_params.length == 0, "INVALID_PARAMS");
        return keccak256("executeOperation()");
    }
