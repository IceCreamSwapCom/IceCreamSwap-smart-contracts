// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IAggregatorExecutor.sol";

contract AggregatorGuard {

    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event AggregatedTrade(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        address executor,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minAmountOut
    );

    receive() external payable { }
    fallback() external payable { } // optional, add for remix to allow low level interactions

    function IceCreamSwap() external payable returns (uint256 amountOut) {
        IAggregatorExecutor executor;
        uint128 amountIn;
        uint128 minAmountOut;

        address firstTokenReceiver;
        address recipient;
        IERC20 tokenIn;
        IERC20 tokenOut;

        assembly {
            executor := shr(96, calldataload(4))
            amountIn := shr(128, calldataload(24))
            minAmountOut := shr(128, calldataload(40))
            firstTokenReceiver := shr(96, calldataload(57))
            recipient := shr(96, calldataload(77))
            tokenIn := shr(96, calldataload(97))
            tokenOut := shr(96, calldataload(117))
        }

        if (address(tokenIn) != ETH) {
            // no need to check this token transfer, as a non sucessfull transfer would just cause a failed swap
            if (amountIn != 0) {
                tokenIn.transferFrom(msg.sender, firstTokenReceiver, amountIn);
            }
        } else {
            require(amountIn == msg.value, "incorrect value");
        }

        uint256 balanceBefore = (address(tokenOut) == ETH) ? recipient.balance : tokenOut.balanceOf(recipient);

        executor.executeSwap{value: msg.value}(msg.data[24:]);

        if (address(tokenOut) != ETH) {
            amountOut = tokenOut.balanceOf(recipient) - balanceBefore;
        } else {
            amountOut = recipient.balance - balanceBefore;
        }
        require(amountOut >= minAmountOut, "Insufficient output");

        emit AggregatedTrade(
            recipient,
            address(tokenIn),
            address(tokenOut),
            address(executor),
            amountIn,
            amountOut,
            minAmountOut
        );
    }
}
