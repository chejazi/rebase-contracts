// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ReToken.sol";

interface Rebased {
    function onStake(address user, address token, uint quantity) external;
    function onUnstake(address user, address token, uint quantity) external;
}

interface WETH {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

contract Rebase is ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using SafeMath for uint256;

    struct User {
        EnumerableSet.AddressSet apps;
        mapping(address => EnumerableMap.AddressToUintMap) appTokenStakes;
    }

    EnumerableMap.UintToAddressMap private _tokenReToken;
    mapping(address => User) private _users;
    mapping(address => EnumerableMap.AddressToUintMap) private _appTokenStakes;
    mapping(address => EnumerableSet.AddressSet) private _appUsers;

    address private constant _WETH = 0x4200000000000000000000000000000000000006;
    address private immutable _clonableToken;

    uint public constant UNRESTAKE_GAS_LIMIT = 1000000;

    event Stake (
        address indexed user,
        address indexed app,
        address indexed token,
        uint quantity
    );

    event Unstake (
        address indexed user,
        address indexed app,
        address indexed token,
        uint quantity,
        bool forced
    );

    constructor() {
        _clonableToken = address(new ReToken());
    }

    receive() external payable { }

    function stake(address token, uint quantity, address app) external nonReentrant {
        require(ERC20(token).transferFrom(msg.sender, address(this), quantity), "Unable to transfer token");
        _getReToken(token).mint(msg.sender, quantity);
        _stake(app, token, quantity);
    }

    function stakeETH(address app) external payable nonReentrant {
        WETH(_WETH).deposit{value: msg.value}();
        _getReToken(_WETH).mint(msg.sender, msg.value);
        _stake(app, _WETH, msg.value);
    }

    function unstake(address token, uint quantity, address app) external nonReentrant {
        _unstake(app, token, quantity);
        _getReToken(token).burn(msg.sender, quantity);
        require(ERC20(token).transfer(msg.sender, quantity), "Unable to transfer token");
    }

    function unstakeETH(uint quantity, address app) external nonReentrant {
        _unstake(app, _WETH, quantity);
        _getReToken(_WETH).burn(msg.sender, quantity);
        WETH(_WETH).withdraw(quantity);
        (bool transferred,) = msg.sender.call{value: quantity}("");
        require(transferred, "Transfer failed");
    }

    function restake(address token, uint quantity, address fromApp, address toApp) external nonReentrant {
        _unstake(fromApp, token, quantity);
        _stake(toApp, token, quantity);
    }

    function _stake(address app, address token, uint quantity) internal {
        User storage user = _users[msg.sender];
        (,uint userStake) = user.appTokenStakes[app].tryGet(token);
        (,uint appStake) = _appTokenStakes[app].tryGet(token);

        require(quantity > 0, "Invalid token quantity");

        user.apps.add(app);
        user.appTokenStakes[app].set(token, userStake.add(quantity));
        _appTokenStakes[app].set(token, appStake.add(quantity));
        _appUsers[app].add(msg.sender);

        Rebased(app).onStake(msg.sender, token, quantity);

        emit Stake(msg.sender, app, token, quantity);
    }

    function _unstake(address app, address token, uint quantity) internal {
        User storage user = _users[msg.sender];
        (,uint userStake) = user.appTokenStakes[app].tryGet(token);
        (,uint appStake) = _appTokenStakes[app].tryGet(token);

        require(quantity > 0 && quantity <= userStake, "Invalid token quantity");

        if (userStake == quantity) {
            user.appTokenStakes[app].remove(token);
            if (user.appTokenStakes[app].length() == 0) {
                user.apps.remove(app);
                _appUsers[app].remove(msg.sender);
            }
        } else {
            user.appTokenStakes[app].set(token, userStake.sub(quantity));
        }
        _appTokenStakes[app].set(token, appStake.sub(quantity));

        bool forced = false;
        try Rebased(app).onUnstake{gas: UNRESTAKE_GAS_LIMIT}(msg.sender, token, quantity) { }
        catch { forced = true; }

        emit Unstake(msg.sender, app, token, quantity, forced);
    }

    function _getReToken(address token) internal returns (ReToken) {
        uint tokenId = _tokenToId(token);
        (bool exists, address reToken) = _tokenReToken.tryGet(tokenId);
        if (!exists) {
            reToken = Clones.cloneDeterministic(_clonableToken, bytes32(tokenId));
            ReToken(reToken).initialize(token);
            _tokenReToken.set(tokenId, reToken);
        }
        return ReToken(reToken);
    }

    function _tokenToId(address token) internal pure returns (uint) {
        return uint(uint160(token));
    }

    function getUserApps(address user) external view returns (address[] memory) {
        return _users[user].apps.values();
    }

    function getUserAppAt(address user, uint index) external view returns (address) {
        return _users[user].apps.at(index);
    }

    function getNumUserApps(address user) external view returns (uint) {
        return _users[user].apps.length();
    }

    function getAppUsers(address app) external view returns (address[] memory) {
        return _appUsers[app].values();
    }

    function getAppUserAt(address app, uint index) external view returns (address) {
        return _appUsers[app].at(index);
    }

    function getNumAppUsers(address app) external view returns (uint) {
        return _appUsers[app].length();
    }

    function getAppStake(address app, address token) external view returns (uint) {
        (,uint appStake) = _appTokenStakes[app].tryGet(token);
        return appStake;
    }

    function getAppStakes(address app) external view returns (address[] memory, uint[] memory) {
        EnumerableMap.AddressToUintMap storage appStakes = _appTokenStakes[app];
        address[] memory tokens = appStakes.keys();
        uint[] memory stakes = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            stakes[i] = appStakes.get(tokens[i]);
        }
        return (tokens, stakes);
    }

    function getAppStakeAt(address app, uint index) external view returns (address, uint) {
        return _appTokenStakes[app].at(index);
    }

    function getNumAppStakes(address app) external view returns (uint) {
        return _appTokenStakes[app].length();
    }

    function getUserAppStake(address user, address app, address token) external view returns (uint) {
        (,uint userStake) = _users[user].appTokenStakes[app].tryGet(token);
        return userStake;
    }

    function getUserAppStakes(address user, address app) external view returns (address[] memory, uint[] memory) {
        EnumerableMap.AddressToUintMap storage userStakes = _users[user].appTokenStakes[app];
        address[] memory tokens = userStakes.keys();
        uint[] memory stakes = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            stakes[i] = userStakes.get(tokens[i]);
        }
        return (tokens, stakes);
    }

    function getUserAppStakeAt(address user, address app, uint index) external view returns (address, uint) {
        return _users[user].appTokenStakes[app].at(index);
    }

    function getNumUserAppStakes(address user, address app) external view returns (uint) {
        return _users[user].appTokenStakes[app].length();
    }

    function getReToken(address token) external view returns (address) {
        return _tokenReToken.get(_tokenToId(token));
    }
}
