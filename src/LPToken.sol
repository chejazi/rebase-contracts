// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract LPToken is ERC20 {
    address private constant _rebase = 0x89fA20b30a88811FBB044821FEC130793185c60B;
    address private _deployer;
    address private _token0;
    address private _token1;
    uint24 private _fee;

    modifier onlyDeployer {
        require(msg.sender == _deployer, "Only callable by deployer");
        _;
    }

    constructor() ERC20("", "") {
        _deployer = msg.sender;
    }

    function initialize(address token0, address token1, uint24 fee) external {
        require(_deployer == address(0), "Initialized");
        _deployer = msg.sender;
        _token0 = token0;
        _token1 = token1;
        _fee = fee;
    }

    function name() public view override returns (string memory) {
        return string.concat("Uniswap V3 ", symbol(), " LP ", Strings.toString(_fee), " Fee");
    }

    function symbol() public view override returns (string memory) {
        return string.concat(ERC20(_token0).symbol(),"/",ERC20(_token1).symbol());
    }

    function mint(address to, uint tokens) external onlyDeployer {
        _mint(to, tokens);
        _approve(to, _rebase, type(uint256).max);
    }

    function burn(address from, uint tokens) external onlyDeployer {
        _burn(from, tokens);
    }

    function getPair() external view returns (address, address, uint24) {
        return (_token0, _token1, _fee);
    }
}
