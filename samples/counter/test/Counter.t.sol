// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Counter} from "../src/Counter.sol";

contract CounterTest {
    function testIncrement() public {
        Counter counter = new Counter();
        counter.increment();
        require(counter.number() == 1, "increment failed");
    }

    function testFuzzSetNumber(uint256 value) public {
        Counter counter = new Counter();
        counter.setNumber(value);
        require(counter.number() == value, "round trip failed");
    }
}
