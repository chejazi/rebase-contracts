// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ReToken.sol";

interface Rebased {
    function appname() external returns (string memory);
    function restake(address user, address token, uint quantity) external;
    function unrestake(address user, address token, uint quantity) external;
}

interface WETH {
    function deposit() external payable;
    function withdraw(uint amount) external;
}

contract Rebase is ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using SafeMath for uint256;

    struct User {
        EnumerableSet.AddressSet tokens;
        mapping(address => uint) tokenStake;
        mapping(address => EnumerableSet.AddressSet) tokenApps;
    }

    EnumerableMap.UintToAddressMap private _tokenReToken;
    EnumerableSet.AddressSet private _reTokens;
    mapping(address => uint) private _stakes;
    mapping(address => User) private _users;

    address private constant _WETH = 0x4200000000000000000000000000000000000006;
    address private immutable _clonableToken;

    uint public constant UNRESTAKE_GAS_LIMIT = 1000000;

    event Stake (
        address indexed user,
        address indexed token,
        uint quantity
    );

    event Unstake (
        address indexed user,
        address indexed token,
        uint quantity
    );

    event Restake (
        address indexed app,
        address indexed user,
        address indexed token,
        uint quantity
    );

    event Unrestake (
        address indexed app,
        address indexed user,
        address indexed token,
        uint quantity,
        bool success
    );

    constructor() {
        _clonableToken = address(new ReToken());
    }

    receive() external payable { }

    function stake(address token, uint quantity, address[] memory apps) external nonReentrant {
        User storage user = _users[msg.sender];

        require(!_reTokens.contains(token), "Invalid token");
        require(quantity > 0, "Invalid token quantity");

        require(ERC20(token).transferFrom(msg.sender, address(this), quantity), "Unable to transfer token");
        _getReToken(token).mint(msg.sender, quantity);
        _stakes[token] = _stakes[token].add(quantity);
        user.tokenStake[token] = user.tokenStake[token].add(quantity);
        user.tokens.add(token);

        emit Stake(msg.sender, token, quantity);

        _updateAppStakes(user, token, quantity, apps);
    }

    function stakeETH(address[] memory apps) external payable nonReentrant {
        address token = _WETH;
        uint quantity = msg.value;
        User storage user = _users[msg.sender];

        require(quantity > 0, "Invalid token quantity");

        WETH(_WETH).deposit{value: quantity}();
        _getReToken(token).mint(msg.sender, quantity);
        _stakes[token] = _stakes[token].add(quantity);
        user.tokenStake[token] = user.tokenStake[token].add(quantity);
        user.tokens.add(token);

        emit Stake(msg.sender, token, quantity);

        _updateAppStakes(user, token, quantity, apps);
    }

    function unstake(address token, uint quantity) external nonReentrant {
        User storage user = _users[msg.sender];
        uint tokenStake = user.tokenStake[token];
        bool removeTokenApps = tokenStake == quantity;
        EnumerableSet.AddressSet storage userTokenApps = user.tokenApps[token];
        address[] memory apps = userTokenApps.values();

        require(quantity > 0 && quantity <= tokenStake, "Invalid token quantity");

        for (uint i = 0; i < apps.length; i++) {
            if (!_unrestake(apps[i], token, quantity) || removeTokenApps) {
                userTokenApps.remove(apps[i]);
            }
        }
        if (removeTokenApps) {
            user.tokens.remove(token);
        }

        _getReToken(token).burn(msg.sender, quantity);
        _stakes[token] = _stakes[token].sub(quantity);
        user.tokenStake[token] = tokenStake.sub(quantity);

        if (token == _WETH) {
            WETH(_WETH).withdraw(quantity);
            (bool success,) = msg.sender.call{value: quantity}("");
            require(success, "Transfer failed");
        } else {
            require(ERC20(token).transfer(msg.sender, quantity), "Unable to transfer token");
        }

        emit Unstake(msg.sender, token, quantity);
    }

    function restake(address[] memory apps, address[] memory tokens) external nonReentrant {
        User storage user = _users[msg.sender];

        require(tokens.length == apps.length, "Argument mismatch");

        for (uint i = 0; i < apps.length; i++) {
            address app = apps[i];
            address token = tokens[i];
            uint userStake = user.tokenStake[token];
            if (!user.tokenApps[token].contains(app) && userStake > 0) {
                user.tokenApps[token].add(app);
                user.tokens.add(token);
                _restake(app, token, userStake);
            }
        }
    }

    function unrestake(address[] memory apps, address[] memory tokens) external nonReentrant {
        User storage user = _users[msg.sender];

        require(tokens.length == apps.length, "Argument mismatch");

        for (uint i = 0; i < apps.length; i++) {
            address app = apps[i];
            address token = tokens[i];
            if (user.tokenApps[token].contains(app)) {
                user.tokenApps[token].remove(app);
                if (user.tokenApps[token].length() == 0) {
                    user.tokens.remove(token);
                }
                // Ignore return value since app is removed above
                _unrestake(app, token, user.tokenStake[token]);
            }
        }
    }

    function _updateAppStakes(User storage user, address token, uint addedStake, address[] memory addedApps) internal {
        uint currentStake = user.tokenStake[token];
        EnumerableSet.AddressSet storage userTokens = user.tokens;
        EnumerableSet.AddressSet storage userTokenApps = user.tokenApps[token];
        address[] memory existingApps = userTokenApps.values();

        for (uint i = 0; i < existingApps.length; i++) {
            _restake(existingApps[i], token, addedStake);
        }
        for (uint i = 0; i < addedApps.length; i++) {
            address app = addedApps[i];
            if (!userTokenApps.contains(app)) {
                userTokenApps.add(app);
                userTokens.add(token);
                _restake(app, token, currentStake);
            }
        }
    }

    function _restake(address app, address token, uint quantity) internal {
        try Rebased(app).restake(msg.sender, token, quantity) {
            emit Restake(app, msg.sender, token, quantity);
        } catch {
            revert(string.concat("Unable to restake to app: ", Strings.toHexString(app)));
        }
    }

    function _unrestake(address app, address token, uint quantity) internal returns (bool) {
        try Rebased(app).unrestake{gas: UNRESTAKE_GAS_LIMIT}(msg.sender, token, quantity) {
            emit Unrestake(app, msg.sender, token, quantity, true);
            return true;
        } catch {
            emit Unrestake(app, msg.sender, token, quantity, false);
            return false;
        }
    }

    function _getReToken(address token) internal returns (ReToken) {
        uint tokenId = _tokenToId(token);
        (bool exists, address reToken) = _tokenReToken.tryGet(tokenId);
        if (!exists) {
            reToken = Clones.cloneDeterministic(_clonableToken, bytes32(tokenId));
            ReToken(reToken).initialize(token);
            _tokenReToken.set(tokenId, reToken);
            _reTokens.add(reToken);
        }
        return ReToken(reToken);
    }

    function _tokenToId(address token) internal pure returns (uint) {
        return uint(uint160(token));
    }

    function getUserStakedTokens(address user) external view returns (address[] memory) {
        return _users[user].tokens.values();
    }

    function getUserTokenStake(address user, address token) public view returns (uint) {
        return _users[user].tokenStake[token];
    }

    function getUserTokenApps(address user, address token) external view returns (address[] memory) {
        return _users[user].tokenApps[token].values();
    }

    function getTokenReToken(address token) external view returns (address) {
        return _tokenReToken.get(_tokenToId(token));
    }

    function getTokenStake(address token) external view returns (uint) {
        return _stakes[token];
    }

    function getReTokens() external view returns (address[] memory) {
        return _reTokens.values();
    }

    function getReTokensLength() external view returns (uint) {
        return _reTokens.length();
    }

    function getReTokensAt(uint index) external view returns (address) {
        return _reTokens.at(index);
    }
}
