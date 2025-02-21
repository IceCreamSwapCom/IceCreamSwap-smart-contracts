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
        address firstTokenReceiver;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint128 amountIn;
        uint128 minAmountOut;

        assembly {
            executor := shr(96, calldataload(4))
            firstTokenReceiver := shr(96, calldataload(24))
            tokenIn := shr(96, calldataload(44))
            tokenOut := shr(96, calldataload(64))
            amountIn := shr(128, calldataload(84))
            minAmountOut := shr(128, calldataload(100))
        }

        if (address(tokenIn) != ETH) {
            // no need to check this token transfer, as a non sucessfull transfer would just cause a failed swap
            if (amountIn != 0) {
                tokenIn.transferFrom(msg.sender, firstTokenReceiver, amountIn);
            }
        } else {
            require(amountIn == msg.value, "incorrect value");
        }
        
        uint256 balanceBefore = (address(tokenOut) == ETH) ? msg.sender.balance : tokenOut.balanceOf(msg.sender);

        executor.executeSwap{value: msg.value}(msg.data[24:]);

        if (address(tokenOut) != ETH) {
            amountOut = tokenOut.balanceOf(msg.sender) - balanceBefore;
        } else {
            amountOut = msg.sender.balance - balanceBefore;
        }
        require(amountOut >= minAmountOut, "Insufficient output");

        emit AggregatedTrade(
            msg.sender,
            address(tokenIn),
            address(tokenOut),
            address(executor),
            amountIn,
            amountOut,
            minAmountOut
        );
    }
}
