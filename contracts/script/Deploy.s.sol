// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SeismicPay.sol";

contract DeploySeismicPay is Script {
    function run() external returns (SeismicPay pay) {
        vm.startBroadcast();
        pay = new SeismicPay();
        vm.stopBroadcast();
        console.log("SeismicPay deployed at:", address(pay));
    }
}
