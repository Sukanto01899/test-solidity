// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

interface IBlindBoxConsumer {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

contract MockVRFCoordinator is IVRFCoordinatorV2Plus {
    uint256 public nextRequestId = 1;

    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata
    ) external override returns (uint256 requestId) {
        requestId = nextRequestId;
        nextRequestId += 1;
    }

    function fulfillRandomWords(address consumer, uint256 requestId, uint256 randomWord) external {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        IBlindBoxConsumer(consumer).rawFulfillRandomWords(requestId, words);
    }

    function getSubscription(
        uint256
    )
        external
        pure
        override
        returns (uint96, uint96, uint64, address, address[] memory)
    {
        address[] memory consumers = new address[](0);
        return (0, 0, 0, address(0), consumers);
    }

    function createSubscription() external pure override returns (uint256) {
        return 0;
    }

    function requestSubscriptionOwnerTransfer(
        uint256,
        address
    ) external pure override {}

    function acceptSubscriptionOwnerTransfer(uint256) external pure override {}

    function addConsumer(uint256, address) external pure override {}

    function removeConsumer(uint256, address) external pure override {}

    function cancelSubscription(uint256, address) external pure override {}

    function pendingRequestExists(uint256) external pure override returns (bool) {
        return false;
    }

    function getActiveSubscriptionIds(
        uint256,
        uint256
    ) external pure override returns (uint256[] memory) {
        return new uint256[](0);
    }

    function fundSubscriptionWithNative(uint256) external payable override {}
}
