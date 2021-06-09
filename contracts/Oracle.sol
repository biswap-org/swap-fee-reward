pragma solidity =0.6.6;

import "./libs/SafeMath.sol";
import "./libs/FixedPoint.sol";
import "./libs/OracleLibrary.sol";

contract Oracle {
    using FixedPoint for *;
    using SafeMath for uint;

    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    address public immutable factory;
    address public priceUpdater;
    uint public constant CYCLE = 15 minutes;

    bytes32 INIT_CODE_HASH;

    // mapping from pair address to a list of price observations of that pair
    mapping(address => Observation) public pairObservations;

    constructor(address factory_, bytes32 INIT_CODE_HASH_, address priceUpdater_) public {
        factory = factory_;
        INIT_CODE_HASH = INIT_CODE_HASH_;
        priceUpdater = priceUpdater_;
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'BSWSwapFactory: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'BSWSwapFactory: ZERO_ADDRESS');
    }

    function pairFor(address tokenA, address tokenB) public view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                INIT_CODE_HASH
            ))));
    }

    function update(address tokenA, address tokenB) external {
        require(msg.sender == priceUpdater, 'BSWOracle: Price can update only price updater address');
        address pair = pairFor(tokenA, tokenB);

        Observation storage observation = pairObservations[pair];
        uint timeElapsed = block.timestamp - observation.timestamp;
        require(timeElapsed >= CYCLE, 'BSWOracle: PERIOD_NOT_ELAPSED');
        (uint price0Cumulative, uint price1Cumulative,) = BSWOracleLibrary.currentCumulativePrices(pair);
        observation.timestamp = block.timestamp;
        observation.price0Cumulative = price0Cumulative;
        observation.price1Cumulative = price1Cumulative;
    }


    function computeAmountOut(
        uint priceCumulativeStart, uint priceCumulativeEnd,
        uint timeElapsed, uint amountIn
    ) private pure returns (uint amountOut) {
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed)
        );
        amountOut = priceAverage.mul(amountIn).decode144();
    }


    function consult(address tokenIn, uint amountIn, address tokenOut) external view returns (uint amountOut) {
        address pair = pairFor(tokenIn, tokenOut);
        Observation storage observation = pairObservations[pair];

        if (pairObservations[pair].price0Cumulative == 0 || pairObservations[pair].price1Cumulative == 0){
            return 0;
        }

        uint timeElapsed = block.timestamp - observation.timestamp;
        (uint price0Cumulative, uint price1Cumulative,) = BSWOracleLibrary.currentCumulativePrices(pair);
        (address token0,) = sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return computeAmountOut(observation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(observation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }
}