// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../base/Base.s.sol";
import { DAI } from "./tokens/DAI.sol";
import { USDT } from "./tokens/USDT.sol";
import { USDC } from "./tokens/USDC.sol";
import { BST } from "./tokens/BST.sol";
import { TestnetToken } from "./tokens/TestnetToken.sol";

contract DeployTokenScript is BaseScript {
    function run() public pure {
        console2.log("Please run specific task");
    }

    function deployTestnetToken(string memory name, string memory symbol, uint8 decimals) public broadcast {
        TestnetToken token = new TestnetToken(name, symbol, decimals);
        console2.log("TestnetToken deployed at: ", address(token));
        console2.log("TestnetToken name: ", token.name());
        console2.log("TestnetToken symbol: ", token.symbol());
        console2.log("TestnetToken decimals: ", token.decimals());
    }

    function deployDAI() public broadcast {
        address dai = address(new DAI());
        console2.log("DAI deployed at: ", dai);
    }

    function deployUSDT() public broadcast {
        address usdt = address(new USDT());
        console2.log("USDT deployed at: ", usdt);
    }

    function deployUSDC() public broadcast {
        address usdc = address(new USDC());
        console2.log("USDC deployed at: ", usdc);
    }

    function deployBST(uint256 index) public broadcast {
        string memory name = string.concat("Bepolia Staking Token ", vm.toString(index));
        string memory symbol = string.concat("BST-", vm.toString(index));
        console2.log("BST name: ", name);
        console2.log("BST symbol: ", symbol);
        address bst = address(new BST(name, symbol));
        console2.log("BST deployed at: ", bst);
    }
}
