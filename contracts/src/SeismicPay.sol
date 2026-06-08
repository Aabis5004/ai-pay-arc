// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SeismicPay
/// @notice Shielded payment vault. Native ETH in → shielded balance.
contract SeismicPay {
    mapping(address => suint256) private _balances;

    event Deposited(address indexed user);
    event Transferred(address indexed from, address indexed to);
    event Withdrawn(address indexed user);

    function deposit() external payable {
        require(msg.value > 0, "zero deposit");
        _balances[msg.sender] = _balances[msg.sender] + suint256(msg.value);
        emit Deposited(msg.sender);
    }

    function transfer(address to, suint256 amount) external {
        require(to != address(0), "zero address");
        require(_balances[msg.sender] >= amount, "insufficient");
        _balances[msg.sender] = _balances[msg.sender] - amount;
        _balances[to]        = _balances[to]        + amount;
        emit Transferred(msg.sender, to);
    }

    function withdraw(suint256 amount) external {
        require(_balances[msg.sender] >= amount, "insufficient");
        _balances[msg.sender] = _balances[msg.sender] - amount;
        (bool ok, ) = payable(msg.sender).call{value: uint256(amount)}("");
        require(ok, "withdraw failed");
        emit Withdrawn(msg.sender);
    }

    function balanceOf(address account) external view returns (uint256) {
        require(msg.sender == account, "only owner can read");
        return uint256(_balances[account]);
    }
}
