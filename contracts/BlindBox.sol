// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title BlindBox
 * @notice A production-grade blind box system with Chainlink VRF v2 Plus for verifiable randomness
 * @dev Uses VRF for fair reward distribution across multiple box tiers
 */
contract BlindBox is ReentrancyGuard, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes4 private constant _TRANSFER_SELECTOR = 0xa9059cbb;

    struct BoxConfig {
        uint256 minAmount;
        uint256 maxAmount;
        uint8 numTokensToReward;
        bool enabled;
    }

    struct PendingOpen {
        address user;
        uint8 boxType;
        address coordinator; // Store coordinator to handle config changes
    }

    struct TokenRange {
        uint256 minAmount;
        uint256 maxAmount;
        bool enabled;
    }

    struct TokenRangeInput {
        uint8 boxType;
        address token;
        uint256 minAmount;
        uint256 maxAmount;
        bool enabled;
    }

    struct DebugOpenResult {
        bool contractPaused;
        bool validBox;
        bool boxEnabled;
        bool validRange;
        bool hasRewardTokens;
        bool validRewardCount;
        bool enoughTokens;
        bool freeCooldownPassed;
        uint256 cooldownRemaining;
        bool fidFreeCooldownPassed;
        uint256 fidCooldownRemaining;
        address vrfCoord;
        uint256 subId;
    }

    // Box type constants
    uint8 public constant FREE = 0;
    uint8 public constant SILVER = 1;
    uint8 public constant GOLD = 2;

    // Access control
    address public owner;
    address public pendingOwner;

    // VRF Configuration
    address public vrfCoordinator;
    bytes32 public keyHash;
    uint256 public subscriptionId;
    uint16 public requestConfirmations;
    uint32 public callbackGasLimit;
    bool public nativePayment;
    address public signerAddress;

    // Reward tokens
    address[] public rewardTokens;
    mapping(address => bool) public rewardTokenExists;

    // Box configurations
    mapping(uint8 => BoxConfig) public boxConfigs;
    mapping(uint8 => uint256) public boxPrices;
    mapping(uint8 => mapping(address => TokenRange)) public tokenRanges;

    // Request tracking
    mapping(uint256 => PendingOpen) public pendingOpens;
    uint256 public pendingRequestCount;

    // User rewards and tracking
    mapping(address => mapping(address => uint256)) public pendingRewards;
    mapping(address => uint256) public lastFreeOpenAt;
    mapping(uint256 => uint256) public lastFreeOpenAtByFid;
    mapping(address => address) public lastRewardToken;
    mapping(address => uint256) public lastRewardAmount;
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(uint256 => mapping(uint256 => bool)) public usedNoncesByFid;

    // Emergency withdrawal tracking
    mapping(address => uint256) public emergencyWithdrawn;

    // Events
    event OwnershipTransferInitiated(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event BoxConfigUpdated(
        uint8 indexed boxType,
        uint256 minAmount,
        uint256 maxAmount,
        uint8 numTokensToReward,
        bool enabled
    );
    event BoxPriceUpdated(uint8 indexed boxType, uint256 priceWei);
    event TokenRangeUpdated(
        uint8 indexed boxType,
        address indexed token,
        uint256 minAmount,
        uint256 maxAmount,
        bool enabled
    );
    event RewardTokensUpdated(uint256 count);
    event BoxOpened(
        uint256 indexed requestId,
        address indexed user,
        uint8 indexed boxType
    );
    event RewardsQueued(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event RewardClaimed(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event VrfConfigUpdated(
        address coordinator,
        bytes32 keyHash,
        uint256 subscriptionId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        bool nativePayment
    );
    event PendingOpenCanceled(
        uint256 indexed requestId,
        address indexed user,
        uint8 indexed boxType
    );
    event EmergencyWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event SignerUpdated(address indexed signer);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier validBoxType(uint8 boxType) {
        require(boxType <= GOLD, "Invalid box type");
        _;
    }

    /**
     * @notice Contract constructor
     * @param _vrfCoordinator Chainlink VRF Coordinator address
     * @param _keyHash Gas lane key hash
     * @param _subscriptionId VRF subscription ID
     * @param _requestConfirmations Number of block confirmations
     * @param _callbackGasLimit Gas limit for callback
     * @param _nativePayment Whether to use native token for payment
     * @param initialTokens Initial reward token addresses
     * @param initialRanges Initial per-token ranges
     */
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        bool _nativePayment,
        address[] memory initialTokens,
        TokenRangeInput[] memory initialRanges
    ) {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);

        _setVrfConfig(
            _vrfCoordinator,
            _keyHash,
            _subscriptionId,
            _requestConfirmations,
            _callbackGasLimit,
            _nativePayment
        );

        // Initialize box configurations with sensible defaults
        boxConfigs[FREE] = BoxConfig({
            minAmount: 100e18,
            maxAmount: 250e18,
            numTokensToReward: 1,
            enabled: true
        });
        boxPrices[FREE] = 0;
        boxConfigs[SILVER] = BoxConfig({
            minAmount: 500e18,
            maxAmount: 1000e18,
            numTokensToReward: 2,
            enabled: true
        });
        boxPrices[SILVER] = 0.00003 ether;
        boxConfigs[GOLD] = BoxConfig({
            minAmount: 1000e18,
            maxAmount: 2500e18,
            numTokensToReward: 3,
            enabled: true
        });
        boxPrices[GOLD] = 0.0001 ether;

        _setRewardTokens(initialTokens);
        _setTokenRanges(initialRanges);
    }

    /**
     * @notice Open a blind box and request randomness
     * @param boxType Type of box to open (FREE, SILVER, or GOLD)
     * @param fid Farcaster fid used for free box eligibility
     * @param nonce Anti-replay nonce for signed free box opens
     * @param signature Signature authorizing free box open (ignored for paid boxes)
     * @return requestId The VRF request ID
     */
    function openBox(
        uint8 boxType,
        uint256 fid,
        uint256 nonce,
        bytes calldata signature
    )
        external
        payable
        whenNotPaused
        validBoxType(boxType)
        nonReentrant
        returns (uint256 requestId)
    {
        BoxConfig memory config = boxConfigs[boxType];
        require(config.enabled, "BOX_DISABLED");
        require(config.maxAmount >= config.minAmount, "INVALID_RANGE");
        require(rewardTokens.length > 0, "NO_REWARD_TOKENS");
        require(config.numTokensToReward > 0, "INVALID_REWARD_COUNT");
        require(
            config.numTokensToReward <= rewardTokens.length,
            "NOT_ENOUGH_TOKENS"
        );

        uint256 price = boxPrices[boxType];
        require(msg.value >= price, "INSUFFICIENT_FEE");

        // Check free box cooldown and update timestamp to prevent spamming
        if (boxType == FREE) {
            require(signerAddress != address(0), "SIGNER_NOT_SET");
            require(!usedNonces[msg.sender][nonce], "NONCE_USED");
            require(!usedNoncesByFid[fid][nonce], "FID_NONCE_USED");
            bytes32 messageHash = keccak256(
                abi.encodePacked(
                    msg.sender,
                    fid,
                    boxType,
                    nonce,
                    address(this),
                    block.chainid
                )
            );
            address recoveredSigner = messageHash
                .toEthSignedMessageHash()
                .recover(signature);
            require(recoveredSigner == signerAddress, "Invalid signature");
            usedNonces[msg.sender][nonce] = true;
            usedNoncesByFid[fid][nonce] = true;
            require(
                block.timestamp >= lastFreeOpenAt[msg.sender] + 1 days,
                "FREE_BOX_COOLDOWN"
            );
            require(
                block.timestamp >= lastFreeOpenAtByFid[fid] + 1 days,
                "FID_FREE_BOX_COOLDOWN"
            );
            lastFreeOpenAt[msg.sender] = block.timestamp;
            lastFreeOpenAtByFid[fid] = block.timestamp;
        }

        // Encode extra args for VRF
        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(
            VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment})
        );

        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: 1,
                extraArgs: extraArgs
            });

        // Request only 1 random word (we only need one)
        requestId = IVRFCoordinatorV2Plus(vrfCoordinator).requestRandomWords(
            req
        );

        // Store pending open with current coordinator address
        pendingOpens[requestId] = PendingOpen({
            user: msg.sender,
            boxType: boxType,
            coordinator: vrfCoordinator
        });
        pendingRequestCount += 1;

        if (msg.value > price) {
            (bool refunded, ) = msg.sender.call{value: msg.value - price}("");
            require(refunded, "Refund failed");
        }

        emit BoxOpened(requestId, msg.sender, boxType);
    }

    /**
     * @notice Debug function to check openBox prerequisites
     * @param boxType Type of box to check
     * @param user Address of user
     * @param fid Farcaster fid to check
     * @return result Struct containing all debug flags and values
     */
    function debugOpenBox(
        uint8 boxType,
        address user,
        uint256 fid
    )
        external
        view
        returns (DebugOpenResult memory result)
    {
        result.contractPaused = paused();
        result.validBox = boxType <= GOLD;

        BoxConfig memory config = boxConfigs[boxType];
        result.boxEnabled = config.enabled;
        result.validRange = config.maxAmount >= config.minAmount;
        result.hasRewardTokens = rewardTokens.length > 0;
        result.validRewardCount = config.numTokensToReward > 0;
        result.enoughTokens = config.numTokensToReward <= rewardTokens.length;

        if (boxType == FREE) {
            uint256 nextAllowed = lastFreeOpenAt[user] + 1 days;
            result.freeCooldownPassed = block.timestamp >= nextAllowed;
            result.cooldownRemaining = result.freeCooldownPassed
                ? 0
                : nextAllowed - block.timestamp;
            uint256 nextAllowedFid = lastFreeOpenAtByFid[fid] + 1 days;
            result.fidFreeCooldownPassed = block.timestamp >= nextAllowedFid;
            result.fidCooldownRemaining = result.fidFreeCooldownPassed
                ? 0
                : nextAllowedFid - block.timestamp;
        } else {
            result.freeCooldownPassed = true;
            result.cooldownRemaining = 0;
            result.fidFreeCooldownPassed = true;
            result.fidCooldownRemaining = 0;
        }

        result.vrfCoord = vrfCoordinator;
        result.subId = subscriptionId;
    }

    /**
     * @notice VRF callback function called by coordinator
     * @param requestId The request ID
     * @param randomWords Array of random values from VRF
     */
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        PendingOpen memory pending = pendingOpens[requestId];

        // Validate caller is the coordinator that made the request
        require(msg.sender == pending.coordinator, "Only coordinator");
        require(pending.user != address(0), "Unknown request");
        require(randomWords.length > 0, "No random words");

        delete pendingOpens[requestId];
        require(pendingRequestCount > 0, "No pending requests");
        pendingRequestCount -= 1;

        BoxConfig memory config = boxConfigs[pending.boxType];
        address[] memory pool = _copyRewardTokens();
        uint256 remaining = pool.length;
        uint256 randomWord = randomWords[0];

        // Select tokens and amounts for rewards
        for (uint256 i = 0; i < config.numTokensToReward; i++) {
            uint256 idx = uint256(
                keccak256(abi.encode(randomWord, requestId, i, "token"))
            ) % remaining;
            address token = pool[idx];
            pool[idx] = pool[remaining - 1];
            remaining -= 1;

            (uint256 minAmount, uint256 maxAmount) = _resolveRange(
                pending.boxType,
                token,
                config
            );
            uint256 amount = _randomAmount(
                randomWord,
                requestId,
                i,
                minAmount,
                maxAmount
            );

            pendingRewards[pending.user][token] += amount;
            lastRewardToken[pending.user] = token;
            lastRewardAmount[pending.user] = amount;

            emit RewardsQueued(pending.user, token, amount);
        }
    }

    /**
     * @notice Claim pending rewards for a specific token
     * @param token The token address to claim
     * @return amount The amount claimed
     */
    function claim(
        address token
    ) external whenNotPaused nonReentrant returns (uint256 amount) {
        amount = pendingRewards[msg.sender][token];
        require(amount > 0, "Nothing to claim");

        // Check contract has sufficient balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Insufficient contract balance");

        pendingRewards[msg.sender][token] = 0;

        _safeTransfer(token, msg.sender, amount);
        emit RewardClaimed(msg.sender, token, amount);
    }

    /**
     * @notice Claim all pending rewards across all tokens
     * @dev Uses try-catch to handle individual token failures
     */
    function claimAll() external whenNotPaused nonReentrant {
        bool anySuccess = false;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 amount = pendingRewards[msg.sender][token];

            if (amount > 0) {
                // Check balance before attempting transfer
                uint256 balance = IERC20(token).balanceOf(address(this));

                if (balance >= amount) {
                    pendingRewards[msg.sender][token] = 0;

                    if (_trySafeTransfer(token, msg.sender, amount)) {
                        emit RewardClaimed(msg.sender, token, amount);
                        anySuccess = true;
                    } else {
                        pendingRewards[msg.sender][token] = amount;
                    }
                }
            }
        }

        require(anySuccess, "No rewards claimed");
    }

    /**
     * @notice Get all pending rewards for a user
     * @param user The user address
     * @return tokens Array of token addresses with pending rewards
     * @return amounts Array of pending amounts for each token
     */
    function getPendingRewards(
        address user
    )
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        uint256 count = 0;

        // Count non-zero rewards
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (pendingRewards[user][rewardTokens[i]] > 0) {
                count++;
            }
        }

        tokens = new address[](count);
        amounts = new uint256[](count);
        uint256 idx = 0;

        // Populate arrays
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 amount = pendingRewards[user][token];
            if (amount > 0) {
                tokens[idx] = token;
                amounts[idx] = amount;
                idx++;
            }
        }
    }

    /**
     * @notice Set box configuration
     * @param boxType Box type to configure
     * @param minAmount Minimum reward amount
     * @param maxAmount Maximum reward amount
     * @param numTokensToReward Number of tokens to reward
     * @param enabled Whether the box is enabled
     */
    function setBoxConfig(
        uint8 boxType,
        uint256 minAmount,
        uint256 maxAmount,
        uint8 numTokensToReward,
        bool enabled
    ) external onlyOwner validBoxType(boxType) {
        require(maxAmount >= minAmount, "Invalid range");
        require(minAmount > 0, "Min amount must be > 0");
        require(
            numTokensToReward > 0 || !enabled,
            "Must reward tokens if enabled"
        );

        boxConfigs[boxType] = BoxConfig({
            minAmount: minAmount,
            maxAmount: maxAmount,
            numTokensToReward: numTokensToReward,
            enabled: enabled
        });

        emit BoxConfigUpdated(
            boxType,
            minAmount,
            maxAmount,
            numTokensToReward,
            enabled
        );
    }

    /**
     * @notice Set box price in wei
     * @param boxType Box type to configure
     * @param priceWei Price in wei
     */
    function setBoxPrice(
        uint8 boxType,
        uint256 priceWei
    ) external onlyOwner validBoxType(boxType) {
        boxPrices[boxType] = priceWei;
        emit BoxPriceUpdated(boxType, priceWei);
    }

    /**
     * @notice Set per-token reward range for a specific box type
     * @param boxType Box type to configure
     * @param token Reward token address
     * @param minAmount Minimum reward amount
     * @param maxAmount Maximum reward amount
     * @param enabled Whether to use this per-token range
     */
    function setTokenRange(
        uint8 boxType,
        address token,
        uint256 minAmount,
        uint256 maxAmount,
        bool enabled
    ) external onlyOwner validBoxType(boxType) {
        _setTokenRangeInternal(boxType, token, minAmount, maxAmount, enabled);
    }

    /**
     * @notice Batch set per-token reward ranges
     * @param ranges Array of range configs
     */
    function setTokenRanges(
        TokenRangeInput[] calldata ranges
    ) external onlyOwner {
        _setTokenRanges(ranges);
    }

    /**
     * @notice Get per-token reward range for a specific box type
     * @param boxType Box type to query
     * @param token Reward token address
     */
    function getTokenRange(
        uint8 boxType,
        address token
    ) external view returns (TokenRange memory) {
        return tokenRanges[boxType][token];
    }

    /**
     * @notice Update reward tokens list
     * @param tokens New array of reward token addresses
     */
    function setRewardTokens(address[] calldata tokens) external onlyOwner {
        _setRewardTokens(tokens);
    }

    /**
     * @notice Update VRF configuration
     * @dev Cannot change if there are pending requests
     */
    function setVrfConfig(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        bool _nativePayment
    ) external onlyOwner {
        require(pendingRequestCount == 0, "Pending requests");
        _setVrfConfig(
            _vrfCoordinator,
            _keyHash,
            _subscriptionId,
            _requestConfirmations,
            _callbackGasLimit,
            _nativePayment
        );
    }

    /**
     * @notice Update signer address for free box authorizations
     * @param _signer Address allowed to sign free box authorizations
     */
    function setSignerAddress(address _signer) external onlyOwner {
        require(_signer != address(0), "Zero signer");
        signerAddress = _signer;
        emit SignerUpdated(_signer);
    }

    /**
     * @notice Cancel a pending open request (admin rescue)
     * @param requestId The VRF request ID to cancel
     */
    function cancelPendingOpen(uint256 requestId) external onlyOwner {
        PendingOpen memory pending = pendingOpens[requestId];
        require(pending.user != address(0), "Unknown request");

        delete pendingOpens[requestId];
        require(pendingRequestCount > 0, "No pending requests");
        pendingRequestCount -= 1;

        emit PendingOpenCanceled(requestId, pending.user, pending.boxType);
    }

    /**
     * @notice Initiate ownership transfer (2-step process)
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        require(newOwner != owner, "Same owner");

        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    /**
     * @notice Accept ownership transfer
     */
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");

        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, owner);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal of tokens by owner
     * @param token Token address to withdraw (address(0) for native token)
     * @param to Destination address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        require(amount > 0, "Zero amount");

        if (token == address(0)) {
            // Native token withdrawal
            (bool success, ) = to.call{value: amount}("");
            require(success, "Native transfer failed");
        } else {
            // ERC20 withdrawal
            _safeTransfer(token, to, amount);
        }

        emergencyWithdrawn[token] += amount;
        emit EmergencyWithdrawal(token, to, amount);
    }

    /**
     * @notice Get reward tokens array
     * @return Array of all reward token addresses
     */
    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    /**
     * @notice Get the most recent reward for a user
     * @param user User address
     * @return token Last reward token
     * @return amount Last reward amount
     */
    function getLastReward(
        address user
    ) external view returns (address token, uint256 amount) {
        token = lastRewardToken[user];
        amount = lastRewardAmount[user];
    }

    /**
     * @notice Get box configuration
     * @param boxType Box type to query
     * @return Box configuration struct with min/max amounts and settings
     */
    function getBoxConfig(
        uint8 boxType
    ) external view validBoxType(boxType) returns (BoxConfig memory) {
        return boxConfigs[boxType];
    }

    /**
     * @notice Check if user can open free box (per-wallet cooldown)
     * @param user User address
     * @return Whether user can currently open a free box
     */
    function canOpenFreeBox(address user) external view returns (bool) {
        return block.timestamp >= lastFreeOpenAt[user] + 1 days;
    }

    /**
     * @notice Check if fid can open free box (per-fid cooldown)
     * @param fid Farcaster fid
     * @return Whether fid can currently open a free box
     */
    function canOpenFreeBoxByFid(uint256 fid) external view returns (bool) {
        return block.timestamp >= lastFreeOpenAtByFid[fid] + 1 days;
    }

    /**
     * @notice Get time until next free box (per-wallet cooldown)
     * @param user User address
     * @return Seconds until next free box is available (0 if ready)
     */
    function timeUntilNextFreeBox(
        address user
    ) external view returns (uint256) {
        uint256 nextTime = lastFreeOpenAt[user] + 1 days;
        if (block.timestamp >= nextTime) {
            return 0;
        }
        return nextTime - block.timestamp;
    }

    /**
     * @notice Get time until next free box (per-fid cooldown)
     * @param fid Farcaster fid
     * @return Seconds until next free box is available (0 if ready)
     */
    function timeUntilNextFreeBoxByFid(
        uint256 fid
    ) external view returns (uint256) {
        uint256 nextTime = lastFreeOpenAtByFid[fid] + 1 days;
        if (block.timestamp >= nextTime) {
            return 0;
        }
        return nextTime - block.timestamp;
    }

    /**
     * @notice Internal function to set reward tokens
     * @param tokens Array of token addresses
     */
    function _setRewardTokens(address[] memory tokens) internal {
        require(tokens.length > 0, "Empty tokens array");
        require(tokens.length <= 100, "Too many tokens"); // Reasonable limit

        // Clear existing tokens
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewardTokenExists[rewardTokens[i]] = false;
        }
        delete rewardTokens;

        // Add new tokens (deduplicated)
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            require(token != address(0), "Zero token");

            if (!rewardTokenExists[token]) {
                rewardTokenExists[token] = true;
                rewardTokens.push(token);
            }
        }

        emit RewardTokensUpdated(rewardTokens.length);
    }

    function _setTokenRangeInternal(
        uint8 boxType,
        address token,
        uint256 minAmount,
        uint256 maxAmount,
        bool enabled
    ) internal {
        require(boxType <= GOLD, "Invalid box type");
        require(token != address(0), "Zero token");
        require(maxAmount >= minAmount, "Invalid range");
        tokenRanges[boxType][token] = TokenRange({
            minAmount: minAmount,
            maxAmount: maxAmount,
            enabled: enabled
        });
        emit TokenRangeUpdated(boxType, token, minAmount, maxAmount, enabled);
    }

    function _setTokenRanges(
        TokenRangeInput[] memory ranges
    ) internal {
        for (uint256 i = 0; i < ranges.length; i++) {
            TokenRangeInput memory r = ranges[i];
            _setTokenRangeInternal(
                r.boxType,
                r.token,
                r.minAmount,
                r.maxAmount,
                r.enabled
            );
        }
    }

    function _copyRewardTokens() internal view returns (address[] memory pool) {
        uint256 len = rewardTokens.length;
        pool = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            pool[i] = rewardTokens[i];
        }
    }

    function _resolveRange(
        uint8 boxType,
        address token,
        BoxConfig memory config
    ) internal view returns (uint256 minAmount, uint256 maxAmount) {
        TokenRange memory range = tokenRanges[boxType][token];
        minAmount = range.enabled ? range.minAmount : config.minAmount;
        maxAmount = range.enabled ? range.maxAmount : config.maxAmount;
        require(maxAmount >= minAmount, "INVALID_TOKEN_RANGE");
    }

    /**
     * @notice Internal function to set VRF configuration
     */
    function _setVrfConfig(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        bool _nativePayment
    ) internal {
        require(_vrfCoordinator != address(0), "Zero coordinator");
        require(_subscriptionId > 0, "Invalid subscription");
        require(_callbackGasLimit >= 100000, "Gas limit too low");
        require(_requestConfirmations > 0, "Invalid confirmations");

        vrfCoordinator = _vrfCoordinator;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;
        nativePayment = _nativePayment;

        emit VrfConfigUpdated(
            _vrfCoordinator,
            _keyHash,
            _subscriptionId,
            _requestConfirmations,
            _callbackGasLimit,
            _nativePayment
        );
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(_TRANSFER_SELECTOR, to, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Transfer failed"
        );
    }

    function _trySafeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal returns (bool) {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(_TRANSFER_SELECTOR, to, amount)
        );
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    /**
     * @notice Calculate random amount within range
     * @param randomWord Base random number from VRF
     * @param requestId Request ID for additional entropy
     * @param index Index for additional entropy
     * @param minAmount Minimum amount (inclusive)
     * @param maxAmount Maximum amount (inclusive)
     * @return Random amount in range [minAmount, maxAmount]
     */
    function _randomAmount(
        uint256 randomWord,
        uint256 requestId,
        uint256 index,
        uint256 minAmount,
        uint256 maxAmount
    ) internal pure returns (uint256) {
        // For inclusive range [min, max]: range = max - min + 1
        uint256 range = maxAmount - minAmount + 1;
        uint256 seed = uint256(
            keccak256(abi.encode(randomWord, requestId, index, "amount"))
        );
        return minAmount + (seed % range);
    }

    /**
     * @notice Get comprehensive contract state for debugging
     * @return _owner Contract owner address
     * @return _vrfCoordinator VRF coordinator address
     * @return _subscriptionId VRF subscription ID
     * @return _paused Whether contract is paused
     * @return _rewardTokenCount Number of reward tokens
     * @return freeEnabled Whether FREE box is enabled
     * @return silverEnabled Whether SILVER box is enabled
     * @return goldEnabled Whether GOLD box is enabled
     */
    function getContractState()
        external
        view
        returns (
            address _owner,
            address _vrfCoordinator,
            uint256 _subscriptionId,
            bool _paused,
            uint256 _rewardTokenCount,
            bool freeEnabled,
            bool silverEnabled,
            bool goldEnabled
        )
    {
        _owner = owner;
        _vrfCoordinator = vrfCoordinator;
        _subscriptionId = subscriptionId;
        _paused = paused();
        _rewardTokenCount = rewardTokens.length;
        freeEnabled = boxConfigs[FREE].enabled;
        silverEnabled = boxConfigs[SILVER].enabled;
        goldEnabled = boxConfigs[GOLD].enabled;
    }

    /**
     * @notice Receive function to accept native token
     */
    receive() external payable {}
}
