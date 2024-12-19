// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./RebaseFeeManager.sol";
import "./RewardPool.sol";

interface IRebased {
    function onStake(address user, address token, uint quantity) external;
    function onUnstake(address user, address token, uint quantity) external;
}

contract StakingApp is IRebased, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeMath for uint256;

    RebaseFeeManager private constant _feeManager = RebaseFeeManager(0x74EbF286181962be0d74910b4FE399abCBe9054C);
    address private constant _refi = 0x7dbdBF103Bb03c6bdc584c0699AA1800566f0F84;
    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;
    address private _rewardToken;
    address private _manager;
    EnumerableSet.AddressSet private _tokens;
    mapping(address => EnumerableSet.AddressSet) private _tokenPools;
    mapping(address => EnumerableSet.AddressSet) private _userPools;
    mapping(address => EnumerableMap.AddressToUintMap) private _userTokenStakes;
    address public immutable _poolTemplate;
    uint private _nonce;

    modifier onlyRebase {
        require(msg.sender == _rebase, "Only Rebase");
        _;
    }

    constructor() {
        _poolTemplate = address(new RewardPool());
    }

    function init(address rewardToken, address initialOwner) external {
        require(_rewardToken == address(0), "Already initialized");
        _rewardToken = rewardToken;
        _manager = msg.sender;
        _transferOwnership(initialOwner);
    }

    function updateManager(address manager) external onlyOwner {
        _manager = manager;
    }

    function createStakePool(address token, address funder, uint quantity, uint duration) external returns (address, address) {
        require(
            msg.sender == _manager ||
            msg.sender == owner(),
            "Not authorized"
        );

        address feePool = address(0);
        uint fee = quantity * _feeManager.getTokenFeeRateBips(token) / 10000;
        if (fee > 0) {
            feePool = Clones.cloneDeterministic(address(_poolTemplate), bytes32(_nonce++));
            RewardPool(feePool).init(address(this), fee, duration);
            _tokenPools[_refi].add(feePool);
            _tokens.add(_refi);
        }

        address rewardPool = Clones.cloneDeterministic(address(_poolTemplate), bytes32(_nonce++));
        RewardPool(rewardPool).init(address(this), quantity.sub(fee), duration);
        _tokenPools[token].add(rewardPool);
        _tokens.add(token);

        require(IERC20(_rewardToken).transferFrom(funder, address(this), quantity), "Unable to fund pool");

        return (rewardPool, feePool);
    }

    function onStake(address user, address token, uint quantity) external onlyRebase {
        address[] memory pools = _tokenPools[token].values();
        require(pools.length > 0, "No pools for token");

        EnumerableSet.AddressSet storage userPools = _userPools[user];
        (,uint stake) = _userTokenStakes[user].tryGet(token);
        uint newBalance = stake.add(quantity);

        for (uint i = 0; i < pools.length; i++) {
            address pool = pools[i];
            if (userPools.contains(pool)) {
                RewardPool(pool).add(user, quantity);
            } else {
                userPools.add(pool);
                RewardPool(pool).add(user, newBalance);
            }
        }

        _userTokenStakes[user].set(token, newBalance);
    }

    function onUnstake(address user, address token, uint quantity) external onlyRebase {
        address[] memory pools = _tokenPools[token].values();

        EnumerableSet.AddressSet storage userPools = _userPools[user];
        (,uint stake) = _userTokenStakes[user].tryGet(token);

        require(quantity <= stake, "Invalid unstake amount");

        for (uint i = 0; i < pools.length; i++) {
            address pool = pools[i];
            if (userPools.contains(pool)) {
                RewardPool(pool).remove(user, quantity);
            }
        }

        _userTokenStakes[user].set(token, stake.sub(quantity));
    }

    function syncPools(address[] memory tokens) external {
        EnumerableSet.AddressSet storage userPools = _userPools[msg.sender];

        for (uint j = 0; j < tokens.length; j++) {
            address token = tokens[j];
            (,uint stake) = _userTokenStakes[msg.sender].tryGet(token);

            if (stake > 0) {
                address[] memory pools = _tokenPools[token].values();
                for (uint i = 0; i < pools.length; i++) {
                    address pool = pools[i];

                    if (!userPools.contains(pool)) {
                        userPools.add(pool);
                        RewardPool(pool).add(msg.sender, stake);
                    }
                }
            }
        }
    }

    function claimRewards() external {
        address[] memory pools = _userPools[msg.sender].values();
        for (uint i = 0; i < pools.length; i++) {
            uint reward = RewardPool(pools[i]).payReward(msg.sender);
            if (reward > 0) {
                require(IERC20(_rewardToken).transferFrom(address(this), msg.sender, reward), "Unable to send reward");
            }
        }
    }

    function getRewards(address user) external view returns (uint) {
        uint earned = 0;

        address[] memory pools = _userPools[user].values();
        for (uint i = 0; i < pools.length; i++) {
            earned += RewardPool(pools[i]).earned(user);
        }

        return earned;
    }

    function getTokens() public view returns (address[] memory) {
        return _tokens.values();
    }

    function getTokenAt(uint index) external view returns (address) {
        return _tokens.at(index);
    }

    function getNumTokens() external view returns (uint) {
        return _tokens.length();
    }

    function getUserPools(address user) external view returns (address[] memory) {
        return _userPools[user].values();
    }

    function getUserPoolAt(address user, uint index) external view returns (address) {
        return _userPools[user].at(index);
    }

    function getNumUserPools(address user) external view returns (uint) {
        return _userPools[user].length();
    }

    function getTokenPools(address token) external view returns (address[] memory) {
        return _tokenPools[token].values();
    }

    function getTokenPoolAt(address token, uint index) external view returns (address) {
        return _tokenPools[token].at(index);
    }

    function getNumTokenPools(address token) external view returns (uint) {
        return _tokenPools[token].length();
    }

    function getUserStake(address user, address token) external view returns (uint) {
        (,uint userStake) = _userTokenStakes[user].tryGet(token);
        return userStake;
    }

    function getUserStakes(address user) external view returns (address[] memory, uint[] memory) {
        EnumerableMap.AddressToUintMap storage userStakes = _userTokenStakes[user];
        address[] memory tokens = userStakes.keys();
        uint[] memory stakes = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            stakes[i] = userStakes.get(tokens[i]);
        }
        return (tokens, stakes);
    }

    function getUserStakeAt(address user, uint index) external view returns (address, uint) {
        return _userTokenStakes[user].at(index);
    }

    function getNumUserStakes(address user) external view returns (uint) {
        return _userTokenStakes[user].length();
    }

    function getRewardToken() external view returns (address) {
        return _rewardToken;
    }
}
