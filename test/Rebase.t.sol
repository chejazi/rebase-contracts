// test/MyContract.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Rebase.sol";

contract MyContractTest is Test {
    Rebase myContract;

    function setUp() public {
        myContract = new Rebase();
    }

    function testInitialValue() public {
        assertEq(myContract.value(), 0);
    }

    function testSetValue() public {
        myContract.setValue(42);
        assertEq(myContract.value(), 42);
    }
}