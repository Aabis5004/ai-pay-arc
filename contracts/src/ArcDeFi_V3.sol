// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

contract ArcDeFi_V3 {
    mapping(address => mapping(address => uint256)) public vaultBalance;
    mapping(address => mapping(address => uint256)) public stakedBalance;
    mapping(address => mapping(address => uint256)) public unlockTime;
    uint256 public constant COOLDOWN_PERIOD = 2 minutes; 
    mapping(address => uint256) public totalStaked;
    mapping(address => mapping(address => uint256)) public reserves;
    
    mapping(address => mapping(address => mapping(address => uint256))) public lpBalances;
    mapping(address => mapping(address => uint256)) public totalLpSupply;

    // Events for History Tracking
    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Staked(address indexed user, address indexed token, uint256 amount);
    event Unstaked(address indexed user, address indexed token, uint256 amount);
    event LiquidityAdded(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed user, address tokenA, address tokenB, uint256 amountA, uint256 amountB);
    event Swapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    error TransferFailed();
    error InsufficientLiquidity();
    error CooldownNotFinished(uint256 timeRemaining);
    error InsufficientBalance();
    error ZeroLiquidity();

    function deposit(address token, uint256 amount) external {
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        vaultBalance[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    function transfer(address to, address token, uint256 amount) external {
        if (to == address(0)) revert("Invalid recipient");
        if (amount == 0) revert("Amount must be > 0");
        if (vaultBalance[msg.sender][token] < amount) revert InsufficientBalance();
        
        vaultBalance[msg.sender][token] -= amount;
        vaultBalance[to][token] += amount;
        emit Transferred(msg.sender, to, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        if (amount == 0) revert("Amount must be > 0");
        if (vaultBalance[msg.sender][token] < amount) revert InsufficientBalance();
        
        vaultBalance[msg.sender][token] -= amount;
        if (!IERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
    }

    function stake(address token, uint256 amount) external {
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        stakedBalance[msg.sender][token] += amount;
        totalStaked[token] += amount;
        unlockTime[msg.sender][token] = block.timestamp + COOLDOWN_PERIOD;
        
        emit Staked(msg.sender, token, amount);
    }

    function unstake(address token, uint256 amount) external {
        if (stakedBalance[msg.sender][token] < amount) revert InsufficientBalance();
        uint256 userUnlockTime = unlockTime[msg.sender][token];
        if (block.timestamp < userUnlockTime) revert CooldownNotFinished(userUnlockTime - block.timestamp);

        stakedBalance[msg.sender][token] -= amount;
        totalStaked[token] -= amount;
        if (!IERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
        
        emit Unstaked(msg.sender, token, amount);
    }

    function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external {
        if (!IERC20(tokenA).transferFrom(msg.sender, address(this), amountA)) revert TransferFailed();
        if (!IERC20(tokenB).transferFrom(msg.sender, address(this), amountB)) revert TransferFailed();

        uint256 reserveA = reserves[tokenA][tokenB];
        uint256 reserveB = reserves[tokenB][tokenA];
        uint256 _totalSupply = totalLpSupply[tokenA][tokenB];
        uint256 liquidity;

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - 1000;
            totalLpSupply[tokenA][tokenB] += 1000; 
            totalLpSupply[tokenB][tokenA] += 1000;
        } else {
            liquidity = Math.min((amountA * _totalSupply) / reserveA, (amountB * _totalSupply) / reserveB);
        }

        if (liquidity == 0) revert ZeroLiquidity();

        lpBalances[tokenA][tokenB][msg.sender] += liquidity;
        lpBalances[tokenB][tokenA][msg.sender] += liquidity;
        totalLpSupply[tokenA][tokenB] += liquidity;
        totalLpSupply[tokenB][tokenA] += liquidity;

        reserves[tokenA][tokenB] += amountA;
        reserves[tokenB][tokenA] += amountB;
        
        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB);
    }

    function removeLiquidity(address tokenA, address tokenB, uint256 liquidityAmount) external {
        if (lpBalances[tokenA][tokenB][msg.sender] < liquidityAmount) revert InsufficientBalance();

        uint256 reserveA = reserves[tokenA][tokenB];
        uint256 reserveB = reserves[tokenB][tokenA];
        uint256 _totalSupply = totalLpSupply[tokenA][tokenB];

        uint256 amountA = (liquidityAmount * reserveA) / _totalSupply;
        uint256 amountB = (liquidityAmount * reserveB) / _totalSupply;

        if (amountA == 0 || amountB == 0) revert InsufficientLiquidity();

        lpBalances[tokenA][tokenB][msg.sender] -= liquidityAmount;
        lpBalances[tokenB][tokenA][msg.sender] -= liquidityAmount;
        totalLpSupply[tokenA][tokenB] -= liquidityAmount;
        totalLpSupply[tokenB][tokenA] -= liquidityAmount;

        reserves[tokenA][tokenB] -= amountA;
        reserves[tokenB][tokenA] -= amountB;

        if (!IERC20(tokenA).transfer(msg.sender, amountA)) revert TransferFailed();
        if (!IERC20(tokenB).transfer(msg.sender, amountB)) revert TransferFailed();
        
        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB);
    }

    function getUserLPBalance(address user, address tokenA, address tokenB) external view returns (uint256) {
        return lpBalances[tokenA][tokenB][user];
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        uint256 reserveIn = reserves[tokenIn][tokenOut];
        uint256 reserveOut = reserves[tokenOut][tokenIn];

        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        if (!IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn)) revert TransferFailed();

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        if (amountOut == 0 || amountOut > reserveOut) revert InsufficientLiquidity();

        reserves[tokenIn][tokenOut] += amountIn;
        reserves[tokenOut][tokenIn] -= amountOut;

        if (!IERC20(tokenOut).transfer(msg.sender, amountOut)) revert TransferFailed();
        
        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function getStakeAPR(address token) external view returns (string memory) {
        uint256 tvl = totalStaked[token];
        if (tvl == 0) return "0.00%";
        if (tvl < 1000 * 10**6) return "24.50%";
        if (tvl < 10000 * 10**6) return "18.40%";
        return "12.20%";
    }

    function getPoolFeeAPR(address tokenA, address tokenB) external view returns (string memory) {
        uint256 reserve = reserves[tokenA][tokenB];
        if (reserve == 0) return "0.00%";
        return "11.65%"; 
    }

    function getPoolEmissionAPR(address tokenA, address tokenB) external view returns (string memory) {
        uint256 reserve = reserves[tokenA][tokenB];
        if (reserve == 0) return "0.00%";
        return "22.90%"; 
    }
}
