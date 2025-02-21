// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAggregatorExecutor {
    function executeSwap(bytes calldata swapData) external payable;
}