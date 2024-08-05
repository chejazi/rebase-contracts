// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./ILPNFT.sol";
import "./LPToken.sol";

contract LPWrapper {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using SafeMath for uint256;

    struct Position {
        address lpToken;
        uint128 quantity;
    }

    EnumerableSet.AddressSet private _lpTokens;
    EnumerableMap.UintToAddressMap private _tokenLPToken;
    mapping(address => EnumerableSet.UintSet) private _userPositions;

    mapping(uint => Position) _positions;

    address private immutable _clonableToken;

    ILPNFT private constant _uniV3 = ILPNFT(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);

    event Wrap (
        address indexed owner,
        uint indexed tokenId
    );

    event Unwrap (
        address indexed owner,
        uint indexed tokenId
    );

    constructor() {
        _clonableToken = address(new LPToken());
    }

    function wrap(uint tokenId) external {
        address owner = _uniV3.ownerOf(tokenId);
        require(owner != address(this), "LP NFT Already Wrapped");
        _uniV3.safeTransferFrom(owner, address(this), tokenId);
    }

    function onERC721Received(address /*operator*/, address from, uint256 tokenId, bytes memory /*data*/) external returns (bytes4) {
        require(msg.sender == address(_uniV3), "Not LP NFT Contract");

        (,,address token0,address token1,uint24 fee,int24 minTick,int24 maxTick,uint128 quantity,,,,) = _uniV3.positions(tokenId);

        if (fee == 100) {
            require(minTick == -887272 && maxTick == 887272, "Invalid LP Tick Range");
        } else if (fee == 500) {
            require(minTick == -887270 && maxTick == 887270, "Invalid LP Tick Range");
        } else if (fee == 3000) {
            require(minTick == -887220 && maxTick == 887220, "Invalid LP Tick Range");
        } else if (fee == 10000) {
            require(minTick == -887200 && maxTick == 887200, "Invalid LP Tick Range");
        } else {
            revert("Unsupported Fee");
        }

        address lpToken = _getLPToken(token0, token1, fee);

        _positions[tokenId] = Position({
            quantity: quantity,
            lpToken: lpToken
        });

        _userPositions[from].add(tokenId);

        LPToken(lpToken).mint(from, quantity);

        emit Wrap(from, tokenId);

        return this.onERC721Received.selector;
    }

    function unwrap(uint tokenId) external {
        bool removed = _userPositions[msg.sender].remove(tokenId);
        require(removed, "Not LP owner");

        Position memory p = _positions[tokenId];
        LPToken(p.lpToken).burn(msg.sender, p.quantity);
        delete _positions[tokenId];

        _uniV3.transferFrom(address(this), msg.sender, tokenId);

        emit Unwrap(msg.sender, tokenId);
    }

    function createLPToken(address token0, address token1, uint24 fee) external returns (address) {
        return _getLPToken(token0, token1, fee);
    }

    function _getLPToken(address token0, address token1, uint24 fee) internal returns (address) {
        uint lpTokenKey = _getLPTokenKey(token0, token1, fee);
        (bool exists, address lpToken) = _tokenLPToken.tryGet(lpTokenKey);
        if (!exists) {
            lpToken = Clones.cloneDeterministic(_clonableToken, bytes32(lpTokenKey));
            LPToken(lpToken).initialize(token0, token1, fee);
            _tokenLPToken.set(lpTokenKey, lpToken);
            _lpTokens.add(lpToken);
        }
        return lpToken;
    }

    function _getLPTokenKey(address token0, address token1, uint24 fee) internal pure returns (uint) {
        require(fee == 100 || fee == 500 || fee == 3000 || fee == 10000, "Unsupported Fee");
        require(token0 != token1, "Invalid Pair");

        return uint(keccak256(abi.encode(uint160(token0) ^ uint160(token1), fee)));
    }

    function getUserPositions(address user) external view returns (uint[] memory, address[] memory, uint128[] memory) {
        uint[] memory tokenIds = _userPositions[user].values();
        address[] memory lpTokens = new address[](tokenIds.length);
        uint128[] memory quantities = new uint128[](tokenIds.length);

        for (uint i = 0; i < tokenIds.length; i++) {
            Position memory p = _positions[tokenIds[i]];
            lpTokens[i] = p.lpToken;
            quantities[i] = p.quantity;
        }
        return (tokenIds, lpTokens, quantities);
    }

    function getUserPositionAt(address user, uint index) external view returns (uint, address, uint128) {
        uint tokenId = _userPositions[user].at(index);
        Position memory p = _positions[tokenId];
        return (tokenId, p.lpToken, p.quantity);
    }

    function getLPToken(address token0, address token1, uint24 fee) external view returns (address) {
        uint lpTokenKey = _getLPTokenKey(token0, token1, fee);
        return _tokenLPToken.get(lpTokenKey);
    }

    function getNumUserPositions(address user) external view returns (uint) {
        return _userPositions[user].length();
    }

    function isLPToken(address token) external view returns (bool) {
        return _lpTokens.contains(token);
    }

    function getLPTokens() external view returns (address[] memory) {
        return _lpTokens.values();
    }

    function getLPTokenAt(uint index) external view returns (address) {
        return _lpTokens.at(index);
    }

    function getNumLPTokens() external view returns (uint) {
        return _lpTokens.length();
    }
}
