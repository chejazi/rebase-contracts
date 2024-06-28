pragma solidity ^0.8.0;
import "../src/Rebase.sol";

contract MockApp is Rebased {

    bool private restakingEnabled = true;
    bool private unrestakingEnabled = true;
    bool private infiniteGasUnrestaking = false;
    bool private testReentrancy = false;
    mapping(address => mapping(address => uint)) private userTokenStakes;

    fallback() external payable { }
    receive() external payable { }

    function appname() external pure returns (string memory) {
        return "MockApp";
    }

    function restake(address user, address token, uint quantity) external {
        require(restakingEnabled, "Restaking Disabled");
        userTokenStakes[user][token] += quantity;
        if (testReentrancy) {
            address[] memory noApps = new address[](0);
            Rebase(payable(msg.sender)).stakeETH{value: 1 ether}(noApps);
        }
    }

    function unrestake(address user, address token, uint quantity) external {
        if (unrestakingEnabled) {
            userTokenStakes[user][token] -= quantity;
        } else if (infiniteGasUnrestaking) {
            userTokenStakes[user][token] -= quantity;
            uint i = 1;
            while (i++ != 0) {
                // broken
            }
        } else {
            revert("Unrestaking Disabled");
        }
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

    // Test method to see if unstaking breaks
    function setInfiniteGasUnrestaking() public {
        infiniteGasUnrestaking = true;
    }

    function setReentrancy() public {
        testReentrancy = true;
    }

}
