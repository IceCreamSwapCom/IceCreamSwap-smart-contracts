// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./interfaces/IAggregatorExecutor.sol";
import "./interfaces/IERC20Unsafe.sol";

contract AggregatorGuard {

    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event AggregatedTrade(
        uint16 indexed id,
        address indexed user,
        address tokenIn,
        address tokenOut,
        address executor,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minAmountOut
    );

    receive() external payable { }
    fallback() external payable { } // optional, add for remix to allow low level interactions

    // takes packed calldata
    function IceCreamSwap() external payable returns (uint256) {
        uint16 id;
        IAggregatorExecutor executor;
        uint128 amountIn;
        uint128 minAmountOut;

        address firstTokenReceiver;
        address recipient;
        IERC20Unsafe tokenIn;
        IERC20Unsafe tokenOut;

        assembly ("memory-safe") {
            // low level packed calldata decoding to decrease calldata size
            id := shr(240, calldataload(4))                 // [004-005] 02 bytes
            executor := shr(96, calldataload(6))            // [006-025] 20 bytes
            amountIn := shr(128, calldataload(26))          // [026-041] 16 bytes
            minAmountOut := shr(128, calldataload(42))      // [042-057] 16 bytes
                                                            // [058]     01 byte gab
            firstTokenReceiver := shr(96, calldataload(59)) // [059-078] 20 bytes
            recipient := shr(96, calldataload(79))          // [079-098] 20 bytes
            tokenIn := shr(96, calldataload(99))            // [099-118] 20 bytes
            tokenOut := shr(96, calldataload(119))          // [119-138] 20 bytes
        }

        if (address(tokenIn) == ETH) {
            require(amountIn == msg.value, "incorrect value");
            require(firstTokenReceiver == address(executor), "Native receiver must be executor");
        } else {
            // no need to check this token transfer, as a non successful transfer would just cause a failed swap
            if (amountIn != 0) tokenIn.transferFrom(msg.sender, firstTokenReceiver, amountIn);
        }

        uint256 balanceBefore = (address(tokenOut) == ETH) ? recipient.balance : tokenOut.balanceOf(recipient);

        executor.executeSwap{value: msg.value}(msg.data[26:]);

        uint256 amountOut = ((address(tokenOut) == ETH) ? recipient.balance : tokenOut.balanceOf(recipient)) - balanceBefore;

        require(amountOut >= minAmountOut, "Insufficient output");

        emit AggregatedTrade(
            id,
            recipient,
            address(tokenIn),
            address(tokenOut),
            address(executor),
            amountIn,
            amountOut,
            minAmountOut
        );

        return amountOut;
    }
}
