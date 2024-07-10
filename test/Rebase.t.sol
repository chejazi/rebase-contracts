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
        address app = address(appA);

        address thisAddr = address(this);
        address tokenAddr = address(tokenA);
        address rebaseAddr = address(rebase);

        // Revert if they haven't approved Rebase.
        vm.expectRevert();
        rebase.stake(tokenAddr, 1, app);

        tokenA.approve(address(rebase), type(uint256).max);

        // Revert if they try to stake 0
        vm.expectRevert();
        rebase.stake(tokenAddr, 0, app);

        // Revert if insufficient balance
        vm.expectRevert();
        rebase.stake(tokenAddr, supply + 1, app);

        // Stake supply - 1
        rebase.stake(tokenAddr, supply - 1, app);
        uint stake = rebase.getStake(thisAddr, app, tokenAddr);
        assertEq(stake, supply - 1);

        // Stake 1
        rebase.stake(tokenAddr, 1, app);
        stake = rebase.getStake(thisAddr, app, tokenAddr);
        assertEq(stake, supply);

        address reTokenAddr = rebase.getReToken(tokenAddr);

        uint rebaseBalanceToken = tokenA.balanceOf(rebaseAddr);
        uint userBalanceToken = tokenA.balanceOf(thisAddr);
        uint userBalanceReToken = ERC20(reTokenAddr).balanceOf(thisAddr);

        assertEq(rebaseBalanceToken, supply);
        assertEq(userBalanceToken, 0);
        assertEq(userBalanceReToken, supply);

        // Revert if unstaking 0
        vm.expectRevert();
        rebase.unstake(tokenAddr, 0, app);

        // Transfer reTokens for testing
        ERC20(reTokenAddr).transfer(userA, 1);

        // Revert if insufficient reTokens
        vm.expectRevert();
        rebase.unstake(tokenAddr, supply, app);

        // Transfer reTokens back
        vm.prank(userA);
        ERC20(reTokenAddr).transfer(thisAddr, 1);

        rebase.unstake(tokenAddr, supply - 10, app);

        rebaseBalanceToken = tokenA.balanceOf(rebaseAddr);
        userBalanceToken = tokenA.balanceOf(thisAddr);
        userBalanceReToken = ERC20(reTokenAddr).balanceOf(thisAddr);

        assertEq(rebaseBalanceToken, 10);
        assertEq(userBalanceToken, supply - 10);
        assertEq(userBalanceReToken, 10);

        rebase.unstake(tokenAddr, 10, app);

        rebaseBalanceToken = tokenA.balanceOf(rebaseAddr);
        userBalanceToken = tokenA.balanceOf(thisAddr);
        userBalanceReToken = ERC20(reTokenAddr).balanceOf(thisAddr);

        assertEq(rebaseBalanceToken, 0);
        assertEq(userBalanceToken, supply);
        assertEq(userBalanceReToken, 0);
    }

    function test_stakeUnstakeETH() public {
        address appAAddr = address(appA);
        address appBAddr = address(appB);
        address thisAddr = address(this);
        vm.deal(thisAddr, 10 ether);
        assertEq(thisAddr.balance, 10 ether);

        rebase.stakeETH{value: 1 ether}(appAAddr);
        rebase.stakeETH{value: 2 ether}(appBAddr);

        uint stake = rebase.getStake(thisAddr, appAAddr, productionWeth);
        assertEq(stake, 1 ether);
        stake = rebase.getStake(thisAddr, appBAddr, productionWeth);
        assertEq(stake, 2 ether);

        assertEq(thisAddr.balance, 7 ether);
        assertEq(productionWeth.balance, 3 ether);

        rebase.unstake(productionWeth, 1 ether, appAAddr);

        stake = rebase.getStake(thisAddr, appAAddr, productionWeth);
        assertEq(stake, 0);
        stake = rebase.getStake(thisAddr, appBAddr, productionWeth);
        assertEq(stake, 2 ether);

        assertEq(thisAddr.balance, 8 ether);
        assertEq(productionWeth.balance, 2 ether);
    }

    function test_brokenRestakeUnrestake() public {
        address appAAddr = address(appA);
        address appBAddr = address(appB);
        address thisAddr = address(this);
        address tokenAddr = address(tokenA);
        address rebaseAddr = address(rebase);

        tokenA.approve(rebaseAddr, type(uint256).max);

        // Stake 3 in App A
        rebase.stake(tokenAddr, 3, appAAddr);
        uint stake = rebase.getStake(thisAddr, appAAddr, tokenAddr);
        uint restaked = appA.getStake(thisAddr, tokenAddr);
        address[] memory apps = rebase.getApps(thisAddr);
        assertEq(stake, 3);
        assertEq(restaked, 3);
        assertEq(apps.length, 1);
        assertEq(apps[0], appAAddr);

        // Disable unrestaking
        appA.disableUnrestaking();

        // Unstake 2; unrestake fails but we keep remaining 1 stake
        rebase.unstake(tokenAddr, 2, appAAddr);
        stake = rebase.getStake(thisAddr, appAAddr, tokenAddr);
        restaked = appA.getStake(thisAddr, tokenAddr);
        apps = rebase.getApps(thisAddr);
        assertEq(stake, 1);
        assertEq(restaked, 3);
        assertEq(apps.length, 1);
        assertEq(apps[0], appAAddr);

        rebase.unstake(tokenAddr, 1, appAAddr);
        stake = rebase.getStake(thisAddr, appAAddr, tokenAddr);
        restaked = appA.getStake(thisAddr, tokenAddr);
        apps = rebase.getApps(thisAddr);
        assertEq(stake, 0);
        assertEq(restaked, 3);
        assertEq(apps.length, 0);

        // Stake 1
        rebase.stake(tokenAddr, 2, appBAddr);
        stake = rebase.getStake(thisAddr, appBAddr, tokenAddr);
        restaked = appB.getStake(thisAddr, tokenAddr);
        apps = rebase.getApps(thisAddr);
        assertEq(stake, 2);
        assertEq(restaked, 2);
        assertEq(apps[0], appBAddr);
        assertEq(apps.length, 1);

        // Make app B consume infinite gas unrestaking
        appB.disableUnrestaking();
        appB.setInfiniteGasUnrestaking();
        uint balanceBefore = tokenA.balanceOf(thisAddr);

        // Should remove app
        rebase.unstake(tokenAddr, 1, appBAddr);
        stake = rebase.getStake(thisAddr, appBAddr, tokenAddr);
        restaked = appB.getStake(thisAddr, tokenAddr);
        apps = rebase.getApps(thisAddr);
        assertEq(stake, 1);
        assertEq(restaked, 2); // broken
        assertEq(apps.length, 1);

        uint balanceAfter = tokenA.balanceOf(thisAddr);
        assertEq(balanceBefore, balanceAfter - 1);


        // Should remove app
        rebase.unstake(tokenAddr, 1, appBAddr);
        stake = rebase.getStake(thisAddr, appBAddr, tokenAddr);
        restaked = appB.getStake(thisAddr, tokenAddr);
        apps = rebase.getApps(thisAddr);
        assertEq(stake, 0);
        assertEq(restaked, 2); // broken
        assertEq(apps.length, 0);
        balanceAfter = tokenA.balanceOf(thisAddr);
        assertEq(balanceBefore, balanceAfter - 2);
    }

    function test_reentrancy() public {
        address appAAddr = address(appA);
        address thisAddr = address(this);
        vm.deal(thisAddr, 10 ether);
        assertEq(thisAddr.balance, 10 ether);
        payable(address(appA)).transfer(1 ether);
        rebase.stakeETH{value: 1 ether}(appAAddr);

        appA.setReentrancy();
        vm.expectRevert();
        // should revert because of reentrancy
        rebase.stakeETH{value: 1 ether}(appAAddr);
    }
}