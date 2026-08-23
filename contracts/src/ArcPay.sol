// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ArcPay {
    // user => (token => amount). address(0) is the Native gas token (USDC on Arc).
    mapping(address => mapping(address => uint256)) public balances;

    event Deposited(address indexed user, address indexed token, uint256 amount);
    event Transferred(address indexed from, address indexed to, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);

    // Native token deposit (USDC on Arc)
    function deposit() external payable {
        require(msg.value > 0, "value=0");
        balances[msg.sender][address(0)] += msg.value;
        emit Deposited(msg.sender, address(0), msg.value);
    }

    // ERC20 token deposit (ETH on Arc)
    function depositERC20(address token, uint256 amount) external {
        require(token != address(0), "use deposit()");
        require(amount > 0, "amount=0");
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "transfer failed");
        balances[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    // Transfer either token
    function transfer(address to, address token, uint256 amount) external {
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");
        require(balances[msg.sender][token] >= amount, "insufficient balance");
        
        balances[msg.sender][token] -= amount;
        balances[to][token] += amount;
        
        emit Transferred(msg.sender, to, token, amount);
    }

    // Withdraw Native token
    function withdraw(uint256 amount) external {
        require(amount > 0, "amount=0");
        require(balances[msg.sender][address(0)] >= amount, "insufficient balance");
        
        balances[msg.sender][address(0)] -= amount;
        payable(msg.sender).transfer(amount);
        
        emit Withdrawn(msg.sender, address(0), amount);
    }

    // Withdraw ERC20 token
    function withdrawERC20(address token, uint256 amount) external {
        require(token != address(0), "use withdraw()");
        require(amount > 0, "amount=0");
        require(balances[msg.sender][token] >= amount, "insufficient balance");
        
        balances[msg.sender][token] -= amount;
        require(IERC20(token).transfer(msg.sender, amount), "transfer failed");
        
        emit Withdrawn(msg.sender, token, amount);
    }

    // Helper for balances
    function balanceOf(address account, address token) external view returns (uint256) {
        return balances[account][token];
    }
}
