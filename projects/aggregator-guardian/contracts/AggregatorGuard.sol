// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IAggregatorExecutor.sol";

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

    function IceCreamSwap() external payable returns (uint256) {
        uint16 id;
        IAggregatorExecutor executor;
        uint128 amountIn;
        uint128 minAmountOut;

        address firstTokenReceiver;
        address recipient;
        IERC20 tokenIn;
        IERC20 tokenOut;

        assembly {
            id := shr(240, calldataload(4))
            executor := shr(96, calldataload(6))
            amountIn := shr(128, calldataload(26))
            minAmountOut := shr(128, calldataload(42))
            firstTokenReceiver := shr(96, calldataload(59))
            recipient := shr(96, calldataload(79))
            tokenIn := shr(96, calldataload(99))
            tokenOut := shr(96, calldataload(119))
        }

        if (address(tokenIn) != ETH) {
            // no need to check this token transfer, as a non sucessfull transfer would just cause a failed swap
            if (amountIn != 0) {
                tokenIn.transferFrom(msg.sender, firstTokenReceiver, amountIn);
            }
        } else {
            require(amountIn == msg.value, "incorrect value");
            require(firstTokenReceiver == address(executor), "Native receiver must bee executor");
        }

        uint256 balanceBefore = (address(tokenOut) == ETH) ? recipient.balance : tokenOut.balanceOf(recipient);

        executor.executeSwap{value: msg.value}(msg.data[26:]);

        uint256 amountOut;
        if (address(tokenOut) != ETH) {
            amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
        } else {
            amountOut = recipient.balance - balanceBefore;
        }
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
