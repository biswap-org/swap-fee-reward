pragma solidity 0.6.6;

import "./Ownable.sol";
import "./libs/SafeMath.sol";
import "./libs/EnumerableSet.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IOracle.sol";

interface IBSWFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function INIT_CODE_HASH() external pure returns (bytes32);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function setDevFee(address pair, uint8 _devFee) external;
    function setSwapFee(address pair, uint32 swapFee) external;
}

interface IBSWPair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    function swapFee() external view returns (uint32);
    function devFee() external view returns (uint32);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
    function setSwapFee(uint32) external;
    function setDevFee(uint32) external;
}

interface IBswToken is IERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}

contract SwapFeeReward is Ownable{
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _whitelist;

    address public factory;
    address public router;
    bytes32 public INIT_CODE_HASH;
    uint256 public maxMiningAmount  = 100000000 * 1e18;
    uint256 public maxMiningInPhase = 5000 * 1e18;
    uint public currentPhase = 1;
    uint256 public totalMined = 0;
    IBswToken public bswToken;
    IOracle public oracle;
    address public targetToken;
    
    mapping(address => uint) public nonces;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) public pairOfPid;
    
    struct PairsList {
        address pair;
        uint256 percentReward;
        bool enabled;
    }
    PairsList[] public pairsList;

    event Withdraw(address userAddress, uint256 amount);
    event Rewarded(address account, address input, address output, uint256 amount, uint256 quantity);

    modifier onlyRouter() {
        require(msg.sender == router, "SwapFeeReward: caller is not the router");
        _;
    }

    constructor(
        address _factory,
        address _router,
        bytes32 _INIT_CODE_HASH,
        IBswToken _bswToken,
        IOracle _Oracle,
        address _targetToken
    ) public {
        factory = _factory;
        router = _router;
        INIT_CODE_HASH = _INIT_CODE_HASH;
        bswToken = _bswToken;
        oracle = _Oracle;
        targetToken = _targetToken;
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

    function getSwapFee(address tokenA, address tokenB) internal view returns (uint swapFee) {
        swapFee = uint(1000).sub(IBSWPair(pairFor(tokenA, tokenB)).swapFee());
    }
    
    function setPhase(uint _newPhase) public onlyOwner returns(bool){
        currentPhase = _newPhase;
        return true;
    }

    function checkPairExist(address tokenA, address tokenB) public view returns (bool) {
        address pair = pairFor(tokenA, tokenB);
        PairsList storage pool = pairsList[pairOfPid[pair]];
        if (pool.pair != pair) {
            return false;
        }
        return true;
    }

    function swap(address account, address input, address output, uint256 amount) public onlyRouter returns (bool) {
        if (!isWhitelist(input) || !isWhitelist(output)) {
            return false;
        }
        if (maxMiningAmount <= totalMined){
            return false;
        }
        address pair = pairFor(input, output);
        PairsList storage pool = pairsList[pairOfPid[pair]];
        if (pool.pair != pair || pool.enabled == false) {
            return false;
        }
        uint256 pairFee = getSwapFee(input, output);
        uint256 fee = amount.div(pairFee);
        uint256 quantity = getQuantity(output, fee, targetToken);
        quantity = quantity.mul(pool.percentReward).div(100);
        if (totalMined.add(quantity) > currentPhase.mul(maxMiningInPhase)){
            return false;
        }
        _balances[account] = _balances[account].add(quantity);
        emit Rewarded(account, input, output, amount, quantity);
        return true;
    }

    function rewardBalance(address account) public view returns(uint256){
        return _balances[account];
    }

    function permit(address spender, uint value, uint8 v, bytes32 r, bytes32 s) private {
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(spender, value, nonces[spender]++))));
        address recoveredAddress = ecrecover(message, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == spender, 'SwapFeeReward: INVALID_SIGNATURE');
    }

    function withdraw(uint8 v, bytes32 r, bytes32 s) public returns(bool){
        require(maxMiningAmount > totalMined, 'SwapFeeReward: Mined all tokens');
        uint256 balance = _balances[msg.sender];
        require(totalMined.add(balance) <= currentPhase.mul(maxMiningInPhase), 'SwapFeeReward: Mined all tokens in this phase');
        permit(msg.sender, balance, v, r, s);
        if (balance > 0){
            bswToken.mint(msg.sender, balance);
            _balances[msg.sender] = _balances[msg.sender].sub(balance);
            emit Withdraw(msg.sender, balance);
            totalMined = totalMined.add(balance);
            return true;
        }
        return false;
    }

    function getQuantity(address outputToken, uint256 outputAmount, address anchorToken) public view returns (uint256) {
        uint256 quantity = 0;
        if (outputToken == anchorToken) {
            quantity = outputAmount;
        } else if (IBSWFactory(factory).getPair(outputToken, anchorToken) != address(0) && checkPairExist(outputToken, anchorToken)) {
            quantity = IOracle(oracle).consult(outputToken, outputAmount, anchorToken);
        } else {
            uint256 length = getWhitelistLength();
            for (uint256 index = 0; index < length; index++) {
                address intermediate = getWhitelist(index);
                if (IBSWFactory(factory).getPair(outputToken, intermediate) != address(0) && IBSWFactory(factory).getPair(intermediate, anchorToken) != address(0) && checkPairExist(intermediate, anchorToken)) {
                    uint256 interQuantity = IOracle(oracle).consult(outputToken, outputAmount, intermediate);
                    quantity = IOracle(oracle).consult(intermediate, interQuantity, anchorToken);
                    break;
                }
            }
        }
        return quantity;
    }

    function addWhitelist(address _addToken) public onlyOwner returns (bool) {
        require(_addToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.add(_whitelist, _addToken);
    }

    function delWhitelist(address _delToken) public onlyOwner returns (bool) {
        require(_delToken != address(0), "SwapMining: token is the zero address");
        return EnumerableSet.remove(_whitelist, _delToken);
    }

    function getWhitelistLength() public view returns (uint256) {
        return EnumerableSet.length(_whitelist);
    }

    function isWhitelist(address _token) public view returns (bool) {
        return EnumerableSet.contains(_whitelist, _token);
    }

    function getWhitelist(uint256 _index) public view returns (address){
        require(_index <= getWhitelistLength() - 1, "SwapMining: index out of bounds");
        return EnumerableSet.at(_whitelist, _index);
    }

    function setRouter(address newRouter) public onlyOwner {
        require(newRouter != address(0), "SwapMining: new router is the zero address");
        router = newRouter;
    }

    function setOracle(IOracle _oracle) public onlyOwner {
        require(address(_oracle) != address(0), "SwapMining: new oracle is the zero address");
        oracle = _oracle;
    }

    function setFactory(address _factory) public onlyOwner {
        require(_factory != address(0), "SwapMining: new factory is the zero address");
        factory = _factory;
    }

    function setInitCodeHash(bytes32 _INIT_CODE_HASH) public onlyOwner {
        INIT_CODE_HASH = _INIT_CODE_HASH;
    }

    function pairsListLength() public view returns (uint256) {
        return pairsList.length;
    }

    function addPair(uint256 _percentReward, address _pair) public onlyOwner {
        require(_pair != address(0), "_pair is the zero address");
        pairsList.push(
            PairsList({
                pair: _pair,
                percentReward: _percentReward,
                enabled: true
            })
        );
        pairOfPid[_pair] = pairsListLength() - 1;

    }

    function setPair(uint256 _pid, uint256 _percentReward) public onlyOwner {
        pairsList[_pid].percentReward = _percentReward;
    }

    function setPairEnabled(uint256 _pid, bool _enabled) public onlyOwner {
        pairsList[_pid].enabled = _enabled;
    }
}