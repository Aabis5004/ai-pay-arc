// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CardRegistry
/// @notice Maps a 16-digit card number to a wallet address.
///         Each wallet registers its own card number; lookups resolve a card
///         number back to the owning address so payments can route by card.
contract CardRegistry {
    mapping(uint256 => address) private _cardToAddr;
    mapping(address => uint256) private _addrToCard;

    event Registered(address indexed owner, uint256 indexed cardNumber);

    /// @notice Register the caller's card number. Overwrites caller's prior card.
    function register(uint256 cardNumber) external {
        require(cardNumber != 0, "card=0");
        address existing = _cardToAddr[cardNumber];
        require(existing == address(0) || existing == msg.sender, "card taken");

        // clear old mapping if caller re-registers a different number
        uint256 prev = _addrToCard[msg.sender];
        if (prev != 0 && prev != cardNumber) {
            delete _cardToAddr[prev];
        }

        _cardToAddr[cardNumber] = msg.sender;
        _addrToCard[msg.sender] = cardNumber;
        emit Registered(msg.sender, cardNumber);
    }

    /// @notice Resolve a card number to its owner address (address(0) if unset).
    function addressOf(uint256 cardNumber) external view returns (address) {
        return _cardToAddr[cardNumber];
    }

    /// @notice Get the card number registered by an address (0 if none).
    function cardOf(address owner) external view returns (uint256) {
        return _addrToCard[owner];
    }
}
