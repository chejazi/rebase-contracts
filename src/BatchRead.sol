// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ILPNFT.sol";

contract BatchRead {
    ILPNFT private constant _uniV3 = ILPNFT(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);

    function getTokenMetadata(address[] memory tokens) public view returns (string[] memory, string[] memory, uint[] memory) {
        string[] memory names = new string[](tokens.length);
        string[] memory symbols = new string[](tokens.length);
        uint[] memory decimals = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            ERC20 token = ERC20(tokens[i]);
            names[i] = token.name();
            symbols[i] = token.symbol();
            decimals[i] = token.decimals();
        }
        return (names, symbols, decimals);
    }

    function getLPNFTs(address user) external view returns (uint[] memory, address[] memory, address[] memory) {
        uint numNFTs = _uniV3.balanceOf(user);
        uint[] memory tokenIds = new uint[](numNFTs);
        address[] memory token0s = new address[](numNFTs);
        address[] memory token1s = new address[](numNFTs);
        for (uint i = 0; i < numNFTs; i++) {
            uint tokenId = _uniV3.tokenOfOwnerByIndex(user, i);
            (,,address token0,address token1,,,,,,,,) = _uniV3.positions(tokenId);
            tokenIds[i] = tokenId;
            token0s[i] = token0;
            token1s[i] = token1;
        }
        return (tokenIds, token0s, token1s);
    }
}
