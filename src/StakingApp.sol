// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./Rebase.sol";
import "./RewardPool.sol";

contract StakingApp is Rebased, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeMath for uint256;

    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;
    address private immutable _rewardToken;
    EnumerableSet.AddressSet private _tokens;
    mapping(address => EnumerableSet.AddressSet) private _tokenPools;
    mapping(address => EnumerableSet.AddressSet) private _userPools;
    mapping(address => EnumerableMap.AddressToUintMap) private _userTokenStakes;

    modifier onlyRebase {
        require(msg.sender == _rebase, "Only Rebase");
        _;
    }

    constructor(address rewardToken) {
        _rewardToken = rewardToken;
    }

    function createPool(address[] memory tokens, uint[] memory quantities, uint[] memory durations) external onlyOwner {
        require(tokens.length == quantities.length && tokens.length == durations.length, "Array mismatch");

        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint quantity = quantities[i];
            uint duration = durations[i];

            address pool = address(new RewardPool(quantity, _rewardToken, duration));
            require(ERC20(token).transferFrom(msg.sender, pool, quantity), "Unable to transfer token");
            _tokenPools[token].add(pool);
            _tokens.add(token);
        }
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
            RewardPool(pools[i]).payReward(msg.sender);
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