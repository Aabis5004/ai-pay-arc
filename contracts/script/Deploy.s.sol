// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ArcPay.sol";
import "../src/TestETH.sol";
import "../src/CardRegistry.sol";

contract DeployArc is Script {
    function run() external {
        vm.startBroadcast();
        
        ArcPay pay = new ArcPay();
        TestETH eth = new TestETH();
        CardRegistry registry = new CardRegistry();

        // Mint some initial TestETH to the deployer for testing
        eth.mint(msg.sender, 1000 * 10**18);

        vm.stopBroadcast();
        
        console.log("ArcPay deployed at:", address(pay));
        console.log("TestETH deployed at:", address(eth));
        console.log("CardRegistry deployed at:", address(registry));
    }
}
