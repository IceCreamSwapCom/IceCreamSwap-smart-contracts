// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IERC20Unsafe {
    function balanceOf(address account) external view returns (uint256);

    // no return bool for backwards compatibility with older ERC20 tokens
    // caller need to make sure token transfers which do not revert on failure are tolerable
    function transfer(address recipient, uint256 amount) external;

    // same left out return bool as transfer
    function transferFrom(address sender, address recipient, uint256 amount) external;
}
