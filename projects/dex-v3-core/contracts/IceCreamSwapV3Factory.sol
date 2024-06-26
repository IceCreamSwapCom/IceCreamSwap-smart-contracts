// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import "./interfaces/IPancakeV3Factory.sol";
import "./interfaces/IPancakeV3PoolDeployer.sol";
import "./interfaces/IPancakeV3Pool.sol";

/// @title Canonical PancakeSwap V3 factory
/// @notice Deploys PancakeSwap V3 pools and manages ownership and control over pool protocol fees
contract IceCreamSwapV3Factory is IPancakeV3Factory {
    /// @inheritdoc IPancakeV3Factory
    address public override owner;

    address public immutable poolDeployer;

    /// @inheritdoc IPancakeV3Factory
    mapping(uint24 => int24) public override feeAmountTickSpacing;
    /// @inheritdoc IPancakeV3Factory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;
    /// @inheritdoc IPancakeV3Factory
    mapping(uint24 => TickSpacingExtraInfo) public override feeAmountTickSpacingExtraInfo;
    mapping(address => bool) private _whiteListAddresses;

    address public lmPoolDeployer;

    uint32 public defaultProtocolFee;
    mapping(uint24 => uint32) public defaultProtocolFeeForFee;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyOwnerOrLmPoolDeployer() {
        require(msg.sender == owner || msg.sender == lmPoolDeployer, "Not owner or LM pool deployer");
        _;
    }

    constructor(address _poolDeployer) {
        poolDeployer = _poolDeployer;
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        defaultProtocolFee = 5000;

        feeAmountTickSpacing[1000] = 20;
        feeAmountTickSpacingExtraInfo[1000] = TickSpacingExtraInfo({whitelistRequested: false, enabled: true});
        emit FeeAmountEnabled(1000, 20);
        emit FeeAmountExtraInfoUpdated(500, false, true);
        feeAmountTickSpacing[3000] = 60;
        feeAmountTickSpacingExtraInfo[3000] = TickSpacingExtraInfo({whitelistRequested: false, enabled: true});
        emit FeeAmountEnabled(3000, 60);
        emit FeeAmountExtraInfoUpdated(2500, false, true);
        feeAmountTickSpacing[10000] = 200;
        feeAmountTickSpacingExtraInfo[10000] = TickSpacingExtraInfo({whitelistRequested: false, enabled: true});
        emit FeeAmountEnabled(10000, 200);
        emit FeeAmountExtraInfoUpdated(10000, false, true);
        feeAmountTickSpacing[50000] = 1000;
        feeAmountTickSpacingExtraInfo[50000] = TickSpacingExtraInfo({whitelistRequested: false, enabled: true});
        emit FeeAmountEnabled(50000, 1000);
        emit FeeAmountExtraInfoUpdated(50000, false, true);
    }

    /// @inheritdoc IPancakeV3Factory
    function createPool(address tokenA, address tokenB, uint24 fee) external override returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        TickSpacingExtraInfo memory info = feeAmountTickSpacingExtraInfo[fee];
        require(tickSpacing != 0 && info.enabled, "fee is not available yet");
        if (info.whitelistRequested) {
            require(_whiteListAddresses[msg.sender], "user should be in the white list for this fee tier");
        }
        require(getPool[token0][token1][fee] == address(0));
        pool = IPancakeV3PoolDeployer(poolDeployer).deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IPancakeV3Factory
    function setOwner(address _owner) external override onlyOwner {
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    /// @inheritdoc IPancakeV3Factory
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override onlyOwner {
        require(fee < 1000000);
        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);
        require(feeAmountTickSpacing[fee] == 0);

        feeAmountTickSpacing[fee] = tickSpacing;
        feeAmountTickSpacingExtraInfo[fee] = TickSpacingExtraInfo({whitelistRequested: false, enabled: true});
        emit FeeAmountEnabled(fee, tickSpacing);
        emit FeeAmountExtraInfoUpdated(fee, false, true);
    }

    /// @inheritdoc IPancakeV3Factory
    function setWhiteListAddress(address user, bool verified) public override onlyOwner {
        require(_whiteListAddresses[user] != verified, "state not change");
        _whiteListAddresses[user] = verified;

        emit WhiteListAdded(user, verified);
    }

    /// @inheritdoc IPancakeV3Factory
    function setFeeAmountExtraInfo(uint24 fee, bool whitelistRequested, bool enabled) public override onlyOwner {
        require(feeAmountTickSpacing[fee] != 0);

        feeAmountTickSpacingExtraInfo[fee] = TickSpacingExtraInfo({
            whitelistRequested: whitelistRequested,
            enabled: enabled
        });
        emit FeeAmountExtraInfoUpdated(fee, whitelistRequested, enabled);
    }

    function setLmPoolDeployer(address _lmPoolDeployer) external override onlyOwner {
        lmPoolDeployer = _lmPoolDeployer;
        emit SetLmPoolDeployer(_lmPoolDeployer);
    }

    function getDefaultProtocolFee(uint24 fee) external view override returns (uint32 protocolFee) {
        protocolFee = defaultProtocolFeeForFee[fee];
        if (protocolFee == 0) {
            protocolFee = defaultProtocolFee;
        }
    }

    function setDefaultProtocolFee(uint32 protocolFee) external onlyOwner {
        require(protocolFee <= 10000);
        defaultProtocolFee = protocolFee;
    }

    function setDefaultProtocolFeeForFee(uint32 protocolFee, uint24 fee) external onlyOwner {
        require(protocolFee <= 10000);
        defaultProtocolFeeForFee[fee] = protocolFee;
    }

    function setFeeProtocol(address pool, uint32 feeProtocol0, uint32 feeProtocol1) external override onlyOwner {
        IPancakeV3Pool(pool).setFeeProtocol(feeProtocol0, feeProtocol1);
    }

    function collectProtocol(
        address pool,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override onlyOwner returns (uint128 amount0, uint128 amount1) {
        return IPancakeV3Pool(pool).collectProtocol(recipient, amount0Requested, amount1Requested);
    }

    function setLmPool(address pool, address lmPool) external override onlyOwnerOrLmPoolDeployer {
        IPancakeV3Pool(pool).setLmPool(lmPool);
    }
}
