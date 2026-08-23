// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CardRegistry} from "../src/CardRegistry.sol";

contract DeployRegistry is Script {
    function run() external returns (CardRegistry reg) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        reg = new CardRegistry();
        console.log("CardRegistry deployed at:", address(reg));
        vm.stopBroadcast();
    }
}
