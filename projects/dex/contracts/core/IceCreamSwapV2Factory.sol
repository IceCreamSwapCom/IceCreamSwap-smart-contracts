pragma solidity =0.5.16;

import "./interfaces/IIceCreamSwapV2Factory.sol";
import "./IceCreamSwapV2Pair.sol";

contract IceCreamSwapV2Factory is IIceCreamSwapV2Factory {
    address public feeTo;
    uint8 public feeProtocol;
    address public feeToSetter;

    bytes32 public constant INIT_CODE_HASH = keccak256(abi.encodePacked(type(IceCreamSwapV2Pair).creationCode));

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter, uint8 _feeProtocol) public {
        require(_feeProtocol <= 100, "IceCreamSwapV2: FEE_TO_HIGH");
        feeToSetter = _feeToSetter;
        feeProtocol = _feeProtocol;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function getProtocolFee() external view returns (address, uint8) {
        return (feeTo, feeProtocol);
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "IceCreamSwapV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "IceCreamSwapV2: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "IceCreamSwapV2: PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(IceCreamSwapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IIceCreamSwapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, "IceCreamSwapV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeProtocol(uint8 _feeProtocol) external {
        require(msg.sender == feeToSetter, "IceCreamSwapV2: FORBIDDEN");
        require(_feeProtocol <= 100, "IceCreamSwapV2: FEE_TO_HIGH");
        feeProtocol = _feeProtocol;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, "IceCreamSwapV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
