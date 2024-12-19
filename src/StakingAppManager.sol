// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./StakingApp.sol";

contract StakingAppManager is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    mapping(address => address) private _tokenStakingApps;
    EnumerableSet.AddressSet private _tokens;
    EnumerableSet.AddressSet private _protocols;
    address private _stakingTemplate;
    uint private _nonce;

    modifier onlyProtocol {
        require(_protocols.contains(msg.sender), "Not Authorized");
        _;
    }

    constructor() {
        _stakingTemplate = address(new StakingApp());
    }

    function createStakingApp(address rewardToken, address initialOwner) external onlyProtocol {
        require(_tokens.add(rewardToken), "App already exists");

        address stakingApp = Clones.cloneDeterministic(address(_stakingTemplate), bytes32(_nonce++));
        StakingApp(stakingApp).init(rewardToken, initialOwner);

        _tokenStakingApps[rewardToken] = stakingApp;
    }

    function createStakePool(
        address stakeToken, 
        address rewardToken, 
        address rewardFunder, 
        uint rewardQuantity, 
        uint rewardDuration
    ) onlyProtocol public returns (address, address) {
        address stakingApp = _tokenStakingApps[rewardToken];
        require(stakingApp != address(0), "App does not exist");
        StakingApp app = StakingApp(stakingApp);
        (address rewardPool, address feePool) = app.createStakePool(stakeToken, rewardFunder, rewardQuantity, rewardDuration);
        return (rewardPool, feePool);
    }

    function updateStakingTemplate(address stakingTemplate) onlyOwner external {
        _stakingTemplate = stakingTemplate;
    } 

    function addProtocol(address token) onlyOwner external {
        _protocols.add(token);
    }

    function removeProtocol(address token) onlyOwner external {
        _protocols.remove(token);
    }

    function hasProtocol(address token) external view returns (bool) {
        return _protocols.contains(token);
    }

    function getProtocols() external view returns (address[] memory) {
        return _protocols.values();
    }

    function getTokens() external view returns (address[] memory) {
        return _tokens.values();
    }

    function getTokenAt(uint index) external view returns (address) {
        return _tokens.at(index);
    }

    function getNumTokens() external view returns (uint) {
        return _tokens.length();
    }

    function getStakingApp(address rewardToken) external view returns (address) {
        return _tokenStakingApps[rewardToken];
    }
}
