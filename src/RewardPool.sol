// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RewardPool {
    using SafeMath for uint256;

    address private _rewardDistributor;
    uint256 private _rewardPerTokenStored;
    uint256 private _rewardTotal;
    uint256 private _rewardDuration;
    uint256 private _periodFinish;
    uint256 private _totalSupply;
    uint256 private _lastUpdateTime;
    mapping(address => uint256) private _userRewardPerTokenPaid;
    mapping(address => uint256) private _rewards;
    mapping(address => uint256) private _balances;

    modifier updateReward(address user) {
        _rewardPerTokenStored = rewardPerToken();
        _lastUpdateTime = lastTimeRewardApplicable();
        if (user != address(0)) {
            _rewards[user] = earned(user);
            _userRewardPerTokenPaid[user] = _rewardPerTokenStored;
        }
        _;
    }

    modifier onlyRewardDistributor() {
        require(msg.sender == _rewardDistributor, "Caller is not reward distributor");
        _;
    }

    function init(address distributor, uint reward, uint duration) external {
        require(_rewardDistributor == address(0), "Already Initialized");
        require(reward > 0 && duration > 0, "Invalid reward");
        _rewardDistributor = distributor;
        _rewardTotal = reward;
        _rewardDuration = duration;
        _lastUpdateTime = block.timestamp;
        _periodFinish = block.timestamp.add(_rewardDuration);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        uint endTime = _periodFinish;
        return block.timestamp < endTime ? block.timestamp : endTime;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return _rewardPerTokenStored;
        }
        return
            _rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(_lastUpdateTime)
                    .mul(_rewardTotal)
                    .div(_rewardDuration)
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    function earned(address user) public view returns (uint256) {
        return
            balanceOf(user)
                .mul(rewardPerToken().sub(_userRewardPerTokenPaid[user]))
                .div(1e18)
                .add(_rewards[user]);
    }

    function add(address user, uint256 amount) external onlyRewardDistributor updateReward(user) {
        _totalSupply = _totalSupply.add(amount);
        _balances[user] = _balances[user].add(amount);
    }

    function remove(address user, uint256 amount) external onlyRewardDistributor updateReward(user) {
        _totalSupply = _totalSupply.sub(amount);
        _balances[user] = _balances[user].sub(amount);
    }

    function payReward(address user) external onlyRewardDistributor updateReward(user) returns (uint) {
        uint256 reward = earned(user);
        _rewards[user] = 0;
        return reward;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address user) public view returns (uint256) {
        return _balances[user];
    }

    function getStartTime() public view returns (uint256) {
        return _periodFinish - _rewardDuration;
    }

    function getEndTime() public view returns (uint256) {
        return _periodFinish;
    }

    function getTotalReward() public view returns (uint256) {
        return _rewardTotal;
    }
}
