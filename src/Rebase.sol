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
    function getStake(address user, address token) external view returns (uint);
    function restake(address user, address token, uint quantity) external;
    function unrestake(address user, address token, uint quantity) external;
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
        require(quantity > 0, "Invalid token quantity");
        require(ERC20(token).transferFrom(msg.sender, address(this), quantity), "Unable to transfer token");
        _stake(app, token, quantity);
    }

    function stakeETH(address app) external payable nonReentrant {
        require(msg.value > 0, "Invalid token quantity");
        WETH(_WETH).deposit{value: msg.value}();
        _stake(app, _WETH, msg.value);
    }

    function unstake(address token, uint quantity, address app) external nonReentrant {
        User storage user = _users[msg.sender];
        (,uint staked) = user.appTokenStakes[app].tryGet(token);

        require(quantity > 0 && quantity <= staked, "Invalid token quantity");
        uint newStake = staked.sub(quantity);

        bool forced = false;
        try Rebased(app).unrestake{gas: UNRESTAKE_GAS_LIMIT}(msg.sender, token, quantity) { }
        catch { forced = true; }

        if (newStake == 0) {
            user.appTokenStakes[app].remove(token);
            if (user.appTokenStakes[app].length() == 0) {
                user.apps.remove(app);
            }
        } else {
            user.appTokenStakes[app].set(token, newStake);
        }

        _getReToken(token).burn(msg.sender, quantity);

        if (token == _WETH) {
            WETH(_WETH).withdraw(quantity);
            (bool success,) = msg.sender.call{value: quantity}("");
            require(success, "Transfer failed");
        } else {
            require(ERC20(token).transfer(msg.sender, quantity), "Unable to transfer token");
        }

        emit Unstake(msg.sender, app, token, quantity, forced);
    }

    function _stake(address app, address token, uint quantity) internal {
        User storage user = _users[msg.sender];
        (,uint staked) = user.appTokenStakes[app].tryGet(token);

        _getReToken(token).mint(msg.sender, quantity);

        user.apps.add(app);
        user.appTokenStakes[app].set(token, staked + quantity);

        Rebased(app).restake(msg.sender, token, quantity);

        emit Stake(msg.sender, app, token, quantity);
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

    function getApps(address user) external view returns (address[] memory) {
        return _users[user].apps.values();
    }

    function getApp(address user, uint index) external view returns (address) {
        return _users[user].apps.at(index);
    }

    function getNumApps(address user) external view returns (uint) {
        return _users[user].apps.length();
    }

    function getStake(address user, address app, address token) external view returns (uint) {
        (,uint staked) = _users[user].appTokenStakes[app].tryGet(token);
        return staked;
    }

    function getTokensAndStakes(address user, address app) external view returns (address[] memory, uint[] memory) {
        EnumerableMap.AddressToUintMap storage tokenStakes = _users[user].appTokenStakes[app];
        uint length = tokenStakes.length();
        address[] memory tokens = new address[](length);
        uint[] memory stakes = new uint[](length);
        for (uint i = 0; i < length; i++) {
            (tokens[i], stakes[i]) = tokenStakes.at(i);
        }
        return (tokens, stakes);
    }

    function getTokenAndStake(address user, address app, uint index) external view returns (address, uint) {
        return _users[user].appTokenStakes[app].at(index);
    }

    function getNumTokenStakes(address user, address app) external view returns (uint) {
        return _users[user].appTokenStakes[app].length();
    }

    function getReToken(address token) external view returns (address) {
        return _tokenReToken.get(_tokenToId(token));
    }
}
