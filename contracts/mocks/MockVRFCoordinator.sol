// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBlindBoxConsumer {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

contract MockVRFCoordinator {
    uint256 public nextRequestId = 1;

    function requestRandomWords(
        bytes32,
        uint256,
        uint16,
        uint32,
        uint32,
        bytes calldata
    ) external returns (uint256 requestId) {
        requestId = nextRequestId;
        nextRequestId += 1;
    }

    function fulfillRandomWords(address consumer, uint256 requestId, uint256 randomWord) external {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        IBlindBoxConsumer(consumer).rawFulfillRandomWords(requestId, words);
    }
}
