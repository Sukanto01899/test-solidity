// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Counter {
    uint256 private _value;

    event ValueChanged(uint256 value);

    constructor(uint256 initialValue) {
        _value = initialValue;
        emit ValueChanged(initialValue);
    }

    function current() external view returns (uint256) {
        return _value;
    }

    function increment() external {
        _value += 1;
        emit ValueChanged(_value);
    }

    function set(uint256 newValue) external {
        _value = newValue;
        emit ValueChanged(newValue);
    }
}
