// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";

contract MockTestnetLSTDeployer {
    address public lst;

    constructor(address owner) {
        MockTestnetLST impl = new MockTestnetLST();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");

        lst = address(proxy);
        MockTestnetLST lstContract = MockTestnetLST(payable(lst));
        lstContract.initialize(owner);
    }
}

contract MockTestnetLST is IPOLErrors, OwnableUpgradeable, UUPSUpgradeable, ERC4626Upgradeable {
    uint256 public deployTimestamp;
    uint256 balance; // override this.balance, to avoid computation error on mint

    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
        __ERC4626_init(IERC20(address(0)));
        __ERC20_init("Mock Bepolia LST", "mbLST");
        __UUPSUpgradeable_init();

        deployTimestamp = block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function totalAssets() public view override returns (uint256) {
        // Simulate 5% APY
        uint256 timeElapsed = block.timestamp - deployTimestamp;
        uint256 currentYieldPerc = (timeElapsed * 0.05e18) / 365 days;
        uint256 yield = (balance * currentYieldPerc) / 1e18;

        return balance + yield;
    }

    function mint(address receiver) public payable returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (msg.value > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, msg.value, maxAssets);
        }

        uint256 shares = previewDeposit(msg.value);
        _mint(receiver, shares);

        // update balance
        balance = address(this).balance;
        return shares;
    }

    function mint(uint256, address) public pure override returns (uint256) {
        revert MethodNotAllowed();
    }

    function deposit(uint256, address) public pure override returns (uint256) {
        revert MethodNotAllowed();
    }

    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert MethodNotAllowed();
    }

    function redeem(uint256, address, address) public pure override returns (uint256) {
        revert MethodNotAllowed();
    }

    receive() external payable { }
}
