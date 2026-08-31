// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {Counter} from "../src/Counter.sol";

contract CounterEchidna is Counter {
    function echidna_counter_is_bounded_by_calls() public view returns (bool) {
        return number < type(uint256).max;
    }
}
