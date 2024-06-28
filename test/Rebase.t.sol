// test/Rebase.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Rebase.sol";
import "./MockApp.sol";
import "./MockWETH.sol";
import "./MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RebaseTest is Test {
    Rebase rebase;
    WETH9 weth;
    address productionWeth = 0x4200000000000000000000000000000000000006;
    TestERC20 tokenA;
    TestERC20 tokenB;
    MockApp appA;
    MockApp appB;
    uint constant supply = 1 ether * 1000;
    address private constant userA = 0x0000000000000000000000000000000000000001;

    function setUp() public {
        weth = new WETH9();
        vm.etch(productionWeth, address(weth).code);
        rebase = new Rebase();
        tokenA = new TestERC20("A", supply);
        tokenB = new TestERC20("B", supply);
        appA = new MockApp();
        appB = new MockApp();
    }

    function test_setup() public view {
        assertEq(tokenA.balanceOf(address(this)), supply);
        assertEq(tokenB.balanceOf(address(this)), supply);
    }

    // Receive ETH sent to the contract
    fallback() external payable { }
    receive() external payable { }

    function test_stakeUnstake() public {
        address[] memory apps = new address[](0);

        address thisAddr = address(this);
        address tokenAddr = address(tokenA);
        address rebaseAddr = address(rebase);

        // Revert if they haven't approved Rebase.
        vm.expectRevert();
        rebase.stake(tokenAddr, 1, apps);

        tokenA.approve(address(rebase), type(uint256).max);

        // Revert if they try to stake 0
        vm.expectRevert();
        rebase.stake(tokenAddr, 0, apps);

        // Revert if insufficient balance
        vm.expectRevert();
        rebase.stake(tokenAddr, supply + 1, apps);

        // Stake supply - 1
        rebase.stake(tokenAddr, supply - 1, apps);
        uint stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        assertEq(stake, supply - 1);

        // Stake 1
        rebase.stake(tokenAddr, 1, apps);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        assertEq(stake, supply);

        address reTokenAddr = rebase.getTokenReToken(tokenAddr);

        uint rebaseBalanceToken = tokenA.balanceOf(rebaseAddr);
        uint userBalanceToken = tokenA.balanceOf(thisAddr);
        uint userBalanceReToken = ERC20(reTokenAddr).balanceOf(thisAddr);

        assertEq(rebaseBalanceToken, supply);
        assertEq(userBalanceToken, 0);
        assertEq(userBalanceReToken, supply);

        // Revert if unstaking 0
        vm.expectRevert();
        rebase.unstake(tokenAddr, 0);

        // Transfer reTokens for testing
        ERC20(reTokenAddr).transfer(userA, 1);

        // Revert if insufficient reTokens
        vm.expectRevert();
        rebase.unstake(tokenAddr, supply);

        // Transfer reTokens back
        vm.prank(userA);
        ERC20(reTokenAddr).transfer(thisAddr, 1);

        rebase.unstake(tokenAddr, supply - 10);

        rebaseBalanceToken = tokenA.balanceOf(rebaseAddr);
        userBalanceToken = tokenA.balanceOf(thisAddr);
        userBalanceReToken = ERC20(reTokenAddr).balanceOf(thisAddr);

        assertEq(rebaseBalanceToken, 10);
        assertEq(userBalanceToken, supply - 10);
        assertEq(userBalanceReToken, 10);

        rebase.unstake(tokenAddr, 10);

        rebaseBalanceToken = tokenA.balanceOf(rebaseAddr);
        userBalanceToken = tokenA.balanceOf(thisAddr);
        userBalanceReToken = ERC20(reTokenAddr).balanceOf(thisAddr);

        assertEq(rebaseBalanceToken, 0);
        assertEq(userBalanceToken, supply);
        assertEq(userBalanceReToken, 0);
    }

    function test_stakeUnstakeETH() public {
        address thisAddr = address(this);
        vm.deal(thisAddr, 10 ether);
        assertEq(thisAddr.balance, 10 ether);

        address[] memory apps = new address[](0);
        rebase.stakeETH{value: 1 ether}(apps);

        assertEq(thisAddr.balance, 9 ether);
        assertEq(productionWeth.balance, 1 ether);

        rebase.unstake(productionWeth, 1 ether);

        assertEq(thisAddr.balance, 10 ether);
        assertEq(productionWeth.balance, 0);
    }

    function test_restakeUnrestake() public {
        address appAAddr = address(appA);
        address thisAddr = address(this);
        address tokenAddr = address(tokenA);
        // address rebaseAddr = address(rebase);
        address[] memory apps = new address[](1);
        address[] memory tokens = new address[](1);
        apps[0] = appAAddr;
        tokens[0] = tokenAddr;

        tokenA.approve(address(rebase), type(uint256).max);

        // Stake 1 and add restaking app
        rebase.stake(tokenAddr, 1, apps);
        uint stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        uint restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        address[] memory tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 1);
        assertEq(restaked, 1);
        assertEq(tokenApps[0], appAAddr);
        assertEq(tokenApps.length, 1);

        // Stake 2 and use existing restaking app
        rebase.stake(tokenAddr, 2, apps);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 3);
        assertEq(restaked, 3);
        assertEq(tokenApps[0], appAAddr);
        assertEq(tokenApps.length, 1);

        // Unstake 1 which will unrestake 1
        rebase.unstake(tokenAddr, 1);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 2);
        assertEq(restaked, 2);
        assertEq(tokenApps[0], appAAddr);
        assertEq(tokenApps.length, 1);

        // Unrestake from just the app, keep stake
        rebase.unrestake(apps, tokens);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 2);
        assertEq(restaked, 0);
        assertEq(tokenApps.length, 0);

        // Restake just on the app, keep stake
        rebase.restake(apps, tokens);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 2);
        assertEq(restaked, 2);
        assertEq(tokenApps[0], appAAddr);
        assertEq(tokenApps.length, 1);

        // Unstake all, should remove app
        rebase.unstake(tokenAddr, 2);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 0);
        assertEq(restaked, 0);
        assertEq(tokenApps.length, 0);
    }

    function test_brokenRestakeUnrestake() public {
        address appAAddr = address(appA);
        address appBAddr = address(appB);
        address thisAddr = address(this);
        address tokenAddr = address(tokenA);
        address rebaseAddr = address(rebase);

        address[] memory noApps = new address[](0);

        address[] memory singleApp = new address[](1);
        singleApp[0] = appAAddr;

        address[] memory twoApps = new address[](2);
        twoApps[0] = appAAddr;
        twoApps[1] = appBAddr;

        address[] memory tokens = new address[](1);
        tokens[0] = tokenAddr;

        tokenA.approve(rebaseAddr, type(uint256).max);

        // Stake 3 and add restaking app
        rebase.stake(tokenAddr, 3, singleApp);
        uint stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        uint restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        address[] memory tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 3);
        assertEq(restaked, 3);
        assertEq(tokenApps.length, 1);

        // Stake 1 and restake on two apps
        rebase.stake(tokenAddr, 3, twoApps);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restaked = appA.getUserTokenStake(thisAddr, tokenAddr);
        uint restakedB = appB.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 6);
        assertEq(restakedB, 6);
        assertEq(restaked, 6);
        assertEq(tokenApps.length, 2);

        // Disable unrestaking
        appA.disableUnrestaking();

        // Unstake 2; unrestake fails so we remove appA
        rebase.unstake(tokenAddr, 2);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restakedB = appB.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 4);
        assertEq(restakedB, 4);
        assertEq(tokenApps.length, 1);

        // Stake 1; should go to appB
        rebase.stake(tokenAddr, 1, noApps);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restakedB = appB.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 5);
        assertEq(restakedB, 5);
        assertEq(tokenApps[0], appBAddr);
        assertEq(tokenApps.length, 1);

        // Make app B consume infinite gas unrestaking
        appB.disableUnrestaking();
        appB.setInfiniteGasUnrestaking();

        // Should remove app
        rebase.unstake(tokenAddr, 1);
        stake = rebase.getUserTokenStake(thisAddr, tokenAddr);
        restakedB = appB.getUserTokenStake(thisAddr, tokenAddr);
        tokenApps = rebase.getUserTokenApps(thisAddr, tokenAddr);
        assertEq(stake, 4);
        assertEq(restakedB, 5); // broken
        assertEq(tokenApps.length, 0);
    }

    function test_reentrancy() public {
        address appAAddr = address(appA);
        address thisAddr = address(this);
        vm.deal(thisAddr, 10 ether);
        assertEq(thisAddr.balance, 10 ether);
        payable(address(appA)).transfer(1 ether);
        address[] memory apps = new address[](1);
        apps[0] = appAAddr;
        rebase.stakeETH{value: 1 ether}(apps);

        appA.setReentrancy();
        vm.expectRevert();
        // should revert because of reentrancy
        rebase.stakeETH{value: 1 ether}(apps);
    }
}