pragma solidity ^0.8.0;
import "../src/Rebase.sol";

contract TestApp is Rebased {

    bool private restakingEnabled = true;
    bool private unrestakingEnabled = true;
    mapping(address => mapping(address => uint)) private userTokenStakes;

    function appname() external pure returns (string memory) {
        return "TestApp";
    }

    function restake(address user, address token, uint quantity) external {
        require(restakingEnabled, "Restaking Disabled");
        userTokenStakes[user][token] += quantity;
    }

    function unrestake(address user, address token, uint quantity) external {
        require(unrestakingEnabled, "Unrestaking Disabled");
        userTokenStakes[user][token] -= quantity;
    }

    function getUserTokenStake(address user, address token) public view returns (uint) {
        return userTokenStakes[user][token];
    }

    // Test method to see if staking breaks
    function disableRestaking() public {
        restakingEnabled = false;
    }

    // Test method to see if unstaking breaks
    function disableUnrestaking() public {
        unrestakingEnabled = false;
    }

}
