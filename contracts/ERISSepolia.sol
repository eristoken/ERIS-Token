// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/* 
    ---------------------------------------------------------
    OpenZeppelin Imports
    ---------------------------------------------------------
*/
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20FlashMint} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";

// Chainlink CCIP libraries
import "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import "@chainlink/contracts-ccip/contracts/libraries/Client.sol";

/* 
    ---------------------------------------------------------
    Library for Extended Math (limitLessThan)
    ---------------------------------------------------------
*/
library ExtendedMath {
    function limitLessThan(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

/*
    ---------------------------------------------------------
    Eris Token Sepolia with PoW, Difficulty Adjustment, Faucet, Burn
    ---------------------------------------------------------
*/
contract ERISSepolia is
    ERC20,
    ERC20Permit,
    ERC20Burnable,
    ERC20FlashMint,
    CCIPReceiver
{
    using ExtendedMath for uint;

    // --------------------------------------------
    // Mining & Difficulty Variables
    // --------------------------------------------
    uint public constant MAX_LIMIT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint public latestDifficultyPeriodStarted;
    uint public epochCount;

    uint public constant _BLOCKS_PER_READJUSTMENT = 23; // Discordian retarget period
    uint public constant _MINIMUM_TARGET = 2 ** 16; // Hardest
    uint public constant _MAXIMUM_TARGET = 2 ** 234; // Easiest

    // Difficulty adjustment parameters
    uint private constant _ADJUSTMENT_DIVISOR = 20000; // Divisor for difficulty adjustment calculations (gentler than 2000 = 10x reduction)
    uint private constant _TARGET_BLOCKS_MULTIPLIER = 60; // Multiplier to convert readjustment blocks to target eth blocks
    uint private constant _PERCENTAGE_BASE = 100; // Base value for percentage calculations
    uint private constant _MAX_EXCESS_BLOCK_PCT_EXTRA = 1000; // Maximum extra percentage for excess block adjustments
    uint private constant _MAX_SHORTAGE_BLOCK_PCT_EXTRA = 2000; // Maximum extra percentage for shortage block adjustments (larger than excess to handle inactivity)
    uint private constant _EXTENDED_INACTIVITY_THRESHOLD = 10; // Multiplier threshold for extended inactivity (10x target blocks)
    uint private constant _EXTENDED_INACTIVITY_ADJUSTMENT = 500; // Additional adjustment multiplier for extended inactivity periods

    uint public miningTarget; // Current target
    bytes32 public challengeNumber; // PoW challenge
    uint public rewardEra;
    uint public currentMiningReward; // current block reward
    uint public tokensMinted; // minted supply via PoW

    // --------------------------------------------
    // Reward System - Weighted RNG (23-Based)
    // --------------------------------------------
    uint256 public constant BASE_REWARD_RATE = 23; // Base reward rate (23 tokens per mint)
    
    // Reward Tier Multipliers (23-based Discordian system)
    uint256 public constant TIER_DISCORDANT_MULTIPLIER = 5; // 0.5× (stored as 5/10)
    uint256 public constant TIER_NEUTRAL_MULTIPLIER = 10; // 1.0× (stored as 10/10)
    uint256 public constant TIER_FAVORED_MULTIPLIER = 23; // 2.3× (stored as 23/10)
    uint256 public constant TIER_BLESSED_MULTIPLIER = 50; // 5× (stored as 50/10)
    uint256 public constant TIER_ENIGMA_MULTIPLIER = 230; // 23× (stored as 230/10)
    
    // Tier enum for events
    enum RewardTier {
        Discordant,  // 0 - 45% probability
        Neutral,     // 1 - 30% probability
        Favored,     // 2 - 15% probability
        Blessed,     // 3 - 9% probability
        Enigma23     // 4 - ~1% probability (1 in 23)
    }
    

    // --------------------------------------------
    // Flash Loan Settings
    // --------------------------------------------
    uint256 private constant FLASH_FEE_BASIS_POINTS = 1; // 0.01% fee
    uint256 private constant FLASH_FEE_MIN = 1000; // Min Fee for flashloan
    uint256 private constant FLASH_FEE_MIN_THRESHOLD = 10000; // Amt in wei below where min fee is charged

    // --------------------------------------------
    // PoW Reward Stats
    // --------------------------------------------
    address public lastRewardTo;
    uint public lastRewardAmount;
    uint public lastRewardEthBlockNumber;

    // --------------------------------------------
    // Miner Stats & Leaderboard
    // --------------------------------------------
    // Maximum values for uint128 fields to prevent overflow
    uint128 public constant MAX_TIER_COUNT = type(uint128).max; // 2^128 - 1
    uint128 public constant MAX_SCORE = type(uint128).max; // 2^128 - 1
    
    struct MinerStats {
        uint128 tier1Count; // Discordant
        uint128 tier2Count; // Neutral
        uint128 tier3Count; // Favored
        uint128 tier4Count; // Blessed
        uint128 tier5Count; // Enigma23
        uint128 score;      // Total score (tier1*1 + tier2*2 + tier3*3 + tier4*4 + tier5*5)
    }

    // NOTE: minerStats mapping stores stats for ALL miners who have ever mined
    // The leaderboard array only maintains top 100 for efficient sorted retrieval
    // You can still query stats for ANY miner using getMinerStats() regardless of leaderboard position
    mapping(address => MinerStats) public minerStats; // Stats for ALL miners (not limited to top 100)
    address[] public miners; // Array to track all miner addresses for iteration
    mapping(address => bool) public isRegisteredMiner; // Track if miner is already in the array

    // Sorted leaderboard (top miners by score, descending order)
    // NOTE: This only maintains top MAX_LEADERBOARD_SIZE miners for gas efficiency
    // All miner stats are still accessible via minerStats mapping regardless of leaderboard position
    address[] public leaderboard; // Sorted array of top miners by score (highest first)
    mapping(address => uint256) public leaderboardIndex; // Maps address to their position in leaderboard (1-indexed, 0 = not in leaderboard)
    uint256 public constant MAX_LEADERBOARD_SIZE = 100; // Maximum number of miners in leaderboard

    // --------------------------------------------
    // Faucet
    // --------------------------------------------
    mapping(address => uint256) public lastFaucetClaim;
    uint256 public faucetAmount;
    uint256 public faucetCooldown;

    // --------------------------------------------
    // Admin & Chain Management
    // --------------------------------------------
    address public admin; // Authorized address to manage chains and CCIP settings
    mapping(uint => bool) public allowedChains; // Mapping to track allowed chains

    // --------------------------------------------
    // Chainlink CCIP
    // --------------------------------------------
    IRouterClient private immutable i_router; // CCIP Router for this chain
    mapping(uint64 => bool) public allowedDestinationChains; // Allowed destination chains (CCIP chain selectors)
    mapping(uint64 => string) public chainNames; // Chain selector -> human-readable name
    mapping(string => uint64) public chainSelectorsByName; // Chain name -> chain selector (for user-friendly lookups)
    uint256 public ccipGasLimit; // Gas limit for CCIP message execution on destination chain
    bool public ccipAllowOutOfOrderExecution; // Whether to allow out-of-order execution of CCIP messages

    // --------------------------------------------
    // Events
    // --------------------------------------------
    event Mint(
        address indexed from,
        uint rewardAmount,
        uint epochCount,
        bytes32 newChallengeNumber
    );
    event DifficultyAdjusted(
        uint256 newTarget,
        uint256 newDifficulty,
        uint256 ethBlocksSinceLastDifficultyPeriod
    );
    event NewEpochStarted(uint256 epochCount, bytes32 challengeNumber);
    
    // Tier-specific events (Discordian themed)
    event DiscordantMine(address indexed miner, uint256 reward);
    event NeutralMine(address indexed miner, uint256 reward);
    event ErisFavor(address indexed miner, uint256 reward);
    event DiscordianBlessing(address indexed miner, uint256 reward);
    event Enigma23(address indexed miner, uint256 reward);

    // Miner stats events (optimized - only emits changed tier and new score)
    event MinerStatsUpdated(
        address indexed miner,
        uint256 tier,
        uint256 newScore
    );

    event CrossChainReceived(uint256 amount, address owner, uint64 sourceChain);
    event CrossChainSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChain,
        uint256 amount,
        address owner
    );
    event DestinationChainUpdated(uint64 chainSelector, bool allowed);
    event AllowedChainUpdated(uint256 indexed chainId, bool allowed);
    event AdminUpdated(address oldAdmin, address newAdmin);
    event CCIPExtraArgsUpdated(
        uint256 newGasLimit,
        bool newAllowOutOfOrderExecution
    );

    // Add a new state variable for mining start timestamp
    uint256 public miningStartTimestamp;

    /*
        ---------------------------------------------------------
        Constructor
        ---------------------------------------------------------
    */
    constructor(
        address router
    )
        ERC20("Eris Token", "ERIS")
        ERC20Permit("Eris Token")
        CCIPReceiver(
            router != address(0) ? router : _getRouterForChain(block.chainid)
        )
    {
        // Get router for current chain (use provided router or hardcoded mapping)
        address selectedRouter = router != address(0)
            ? router
            : _getRouterForChain(block.chainid);
        require(
            selectedRouter != address(0),
            "CCIP Router not configured for this chain"
        );

        i_router = IRouterClient(selectedRouter);
        tokensMinted = 0;
        rewardEra = 0;
        // Base PoW reward (23 tokens per mint, multiplied by tier)
        currentMiningReward = BASE_REWARD_RATE * 10 ** decimals();
        // Set placeholder address for admin (update after deployment)
        admin = address(
            0x70c65c7cAB0d5A9EC6A394DDb85C50E2328912e3
        );

        // Initialize CCIP extraArgs with default values
        ccipGasLimit = 200_000; // Default gas limit for CCIP message execution
        ccipAllowOutOfOrderExecution = true; // Default: allow out-of-order execution

        faucetAmount = 1 * 10 ** decimals();
        faucetCooldown = 1 days;

        miningTarget = _MAXIMUM_TARGET;
        latestDifficultyPeriodStarted = block.number;
        challengeNumber = blockhash(block.number - 1);

        // Initialize allowed chains (example: 1 for Ethereum mainnet, 2 for Binance Smart Chain)
        allowedChains[84532] = true; // Coinbase Base Sepolia
        allowedChains[421614] = true; // Arbitrum Sepolia
        allowedChains[97] = true; // BNB Testnet
        // Add more chains as needed

        // Initialize allowed destination chains using CCIP chain selectors
        // Chain selectors are from Chainlink CCIP Directory:
        // Mainnet: https://docs.chain.link/ccip/directory/mainnet
        // Testnet: https://docs.chain.link/ccip/directory/testnet
        // Base Sepolia
        uint64 baseSepoliaSelector = 10344971235874465080;
        allowedDestinationChains[baseSepoliaSelector] = true;
        chainNames[baseSepoliaSelector] = "Base Sepolia";
        chainSelectorsByName["Base Sepolia"] = baseSepoliaSelector;

        // Arbitrum Sepolia
        uint64 arbitrumSepoliaSelector = 3478487238524512106;
        allowedDestinationChains[arbitrumSepoliaSelector] = true;
        chainNames[arbitrumSepoliaSelector] = "Arbitrum Sepolia";
        chainSelectorsByName["Arbitrum Sepolia"] = arbitrumSepoliaSelector;

        // BNB Testnet
        uint64 bnbTestnetSelector = 13264668187771770619;
        allowedDestinationChains[bnbTestnetSelector] = true;
        chainNames[bnbTestnetSelector] = "BNB Testnet";
        chainSelectorsByName["BNB Testnet"] = bnbTestnetSelector;

        miningStartTimestamp = 1766815200; // Set the mining start timestamp
    }

    /*
        ---------------------------------------------------------
        Helper Functions
        ---------------------------------------------------------
    */

    /**
     * @notice Get CCIP Router address for a given chain ID
     * @param chainId The chain ID to get router for
     * @return router The router address for the chain
     * @dev This is a pure function that returns hardcoded router addresses
     */
    function _getRouterForChain(
        uint256 chainId
    ) private pure returns (address router) {
        if (chainId == 97)
            return address(0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f); // BNB Testnet
        if (chainId == 84532)
            return address(0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93); // Base Sepolia
        if (chainId == 421614)
            return address(0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165); // Arbitrum Sepolia
        return address(0);
    }

    /*
        ---------------------------------------------------------
        Chainlink CCIP Implementation
        ---------------------------------------------------------
    */

    /**
     * @notice Initiates a Cross-Chain Bridge Transaction using Chainlink CCIP
     * @param destinationChainName Human-readable name of the destination chain (e.g., "Base Sepolia", "Ethereum Sepolia")
     * @param amount Amount of tokens to bridge (in wei, must be > 0)
     * @dev No signed quote needed - CCIP calculates fees on-chain
     * @dev Receiver is always this contract address due to deterministic deployment
     * @dev Process:
     *      1. Validates amount > 0 and chain name
     *      2. Burns tokens from sender on source chain
     *      3. Sends CCIP message with amount and owner address
     *      4. On destination chain, _ccipReceive() mints tokens to owner
     * @dev Excess fee payment is automatically refunded to sender
     * @dev Emits CrossChainSent event with messageId for tracking
     */
    function sendCCIPCrossChainBridge(
        string memory destinationChainName,
        uint256 amount
    ) external payable {
        require(amount > 0, "Amount must be greater than zero");
        require(
            bytes(destinationChainName).length > 0,
            "Chain name cannot be empty"
        );

        uint64 destinationChainSelector = chainSelectorsByName[
            destinationChainName
        ];
        require(destinationChainSelector != 0, "Invalid chain name");
        require(
            allowedDestinationChains[destinationChainSelector],
            "Destination chain not allowed"
        );

        address owner = msg.sender;

        // Burn tokens from sender
        _burn(owner, amount);

        // Encode payload (amount and owner address)
        bytes memory payload = abi.encode(amount, owner);

        // Create CCIP message
        // Receiver is always this contract address due to deterministic deployment
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)), // Destination contract address (deterministic deployment)
            data: payload, // Encoded payload
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array - no tokens being sent
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: ccipGasLimit, // Configurable gas limit for callback on destination chain
                    allowOutOfOrderExecution: ccipAllowOutOfOrderExecution // Configurable out-of-order execution
                })
            ),
            feeToken: address(0) // Pay fees in native token
        });

        // Get fee estimate from CCIP Router
        uint256 fee = i_router.getFee(destinationChainSelector, evm2AnyMessage);
        require(msg.value >= fee, "Insufficient fee");

        // Send message via CCIP Router
        bytes32 messageId = i_router.ccipSend{value: fee}(
            destinationChainSelector,
            evm2AnyMessage
        );

        // Refund excess payment
        if (msg.value > fee) {
            payable(owner).transfer(msg.value - fee);
        }

        emit CrossChainSent(messageId, destinationChainSelector, amount, owner);
    }

    /**
     * @notice Receives and processes cross-chain messages via CCIP
     * @param message The CCIP message containing cross-chain data
     * @dev This function is automatically called by CCIP Router when message arrives
     * @dev Overrides CCIPReceiver._ccipReceive()
     * @dev Security checks:
     *      1. Verifies source chain is in allowedDestinationChains
     *      2. Verifies sender is this contract (deterministic deployment)
     *      3. Decodes payload to extract amount and owner address
     *      4. Mints tokens to owner on destination chain
     * @dev CCIP handles replay protection natively - no additional checks needed
     * @dev Emits CrossChainReceived event for tracking
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        // Verify source chain is allowed
        require(
            allowedDestinationChains[message.sourceChainSelector],
            "Source chain not allowed"
        );

        // Decode sender address from bytes
        address sender = abi.decode(message.sender, (address));

        // Verify the message came from this contract on the source chain
        // Since the contract is deterministically deployed to the same address on all chains,
        // the sender should always be address(this)
        require(
            sender == address(this),
            "Invalid sender: must be ERIS contract"
        );

        // Decode payload to extract amount and owner
        (uint256 amount, address owner) = abi.decode(
            message.data,
            (uint256, address)
        );

        // Mint tokens to the owner on destination chain
        _mint(owner, amount);

        // Emit event
        emit CrossChainReceived(amount, owner, message.sourceChainSelector);
    }

    /**
     * @notice Add or remove allowed chain for mining (admin function)
     * @param chainId The chain ID to allow or disallow for mining
     * @param allowed Whether mining is allowed on this chain
     * @dev Only callable by the authorized admin address
     */
    function setAllowedChain(uint256 chainId, bool allowed) external {
        require(
            msg.sender == admin,
            "Only admin can set allowed chains"
        );
        require(
            admin != address(0),
            "Admin not configured"
        );

        allowedChains[chainId] = allowed;
        emit AllowedChainUpdated(chainId, allowed);
    }

    /**
     * @notice Add or remove allowed destination chain (admin function)
     * @param chainSelector CCIP chain selector
     * @param allowed Whether chain is allowed
     * @param name Human-readable chain name (optional, for events)
     * @dev Only callable by the authorized admin address
     */
    function setAllowedDestinationChain(
        uint64 chainSelector,
        bool allowed,
        string memory name
    ) external {
        require(
            msg.sender == admin,
            "Only admin can set destination chains"
        );
        require(
            admin != address(0),
            "Admin not configured"
        );

        allowedDestinationChains[chainSelector] = allowed;
        if (bytes(name).length > 0) {
            chainNames[chainSelector] = name;
            chainSelectorsByName[name] = chainSelector;
        }
        emit DestinationChainUpdated(chainSelector, allowed);
    }

    /**
     * @notice Update CCIP extraArgs configuration (admin function)
     * @param newGasLimit New gas limit for CCIP message execution on destination chain
     * @param newAllowOutOfOrderExecution Whether to allow out-of-order execution of CCIP messages
     * @dev Only callable by the authorized admin address
     * @dev This ensures extraArgs remain backward compatible with future CCIP upgrades
     * @dev Recommended to review CCIP service limits before updating gas limit
     * @dev See: https://docs.chain.link/ccip/service-limits
     */
    function setCCIPExtraArgs(
        uint256 newGasLimit,
        bool newAllowOutOfOrderExecution
    ) external {
        require(
            msg.sender == admin,
            "Only admin can set CCIP extraArgs"
        );
        require(
            admin != address(0),
            "Admin not configured"
        );
        require(newGasLimit > 0, "Gas limit must be greater than zero");

        ccipGasLimit = newGasLimit;
        ccipAllowOutOfOrderExecution = newAllowOutOfOrderExecution;

        emit CCIPExtraArgsUpdated(newGasLimit, newAllowOutOfOrderExecution);
    }

    /**
     * @notice Get fee estimate for cross-chain bridge transaction
     * @param destinationChainName Human-readable name of the destination chain (e.g., "Base Sepolia", "Ethereum Sepolia")
     * @param amount Amount to bridge (used for payload size estimation)
     * @return fee Estimated fee in native token (wei)
     * @dev Receiver is always this contract address due to deterministic deployment
     * @dev Fee is calculated by CCIP Router based on destination chain and message size
     * @dev Use this to estimate gas costs before calling sendCCIPCrossChainBridge()
     * @dev Actual fee may vary slightly at execution time
     */
    function getCCIPCrossChainBridgeFee(
        string memory destinationChainName,
        uint256 amount
    ) external view returns (uint256 fee) {
        uint64 destinationChainSelector = chainSelectorsByName[
            destinationChainName
        ];
        require(destinationChainSelector != 0, "Invalid chain name");
        bytes memory payload = abi.encode(amount, msg.sender);

        // Receiver is always this contract address due to deterministic deployment
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(address(this)),
            data: payload,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: ccipGasLimit,
                    allowOutOfOrderExecution: ccipAllowOutOfOrderExecution
                })
            ),
            feeToken: address(0)
        });

        return i_router.getFee(destinationChainSelector, evm2AnyMessage);
    }

    /*
        ---------------------------------------------------------
        Flash Loan Implementation
        ---------------------------------------------------------
    */

    /**
     * @notice Calculates the fee for a flash loan
     * @param token The token address (must be this contract)
     * @param amount The amount being flash loaned
     * @return The flash loan fee in wei
     * @dev Overrides ERC20FlashMint._flashFee() to set custom fee structure
     * @dev Fee structure:
     *      - For amounts > FLASH_FEE_MIN_THRESHOLD (10000 wei): 0.01% fee (FLASH_FEE_BASIS_POINTS)
     *      - For amounts <= FLASH_FEE_MIN_THRESHOLD: Minimum fee of FLASH_FEE_MIN (1000 wei)
     * @dev Example: Flash loan of 1,000,000 tokens = 100 tokens fee (0.01%)
     */
    function _flashFee(
        address token,
        uint256 amount
    ) internal view virtual override returns (uint256) {
        require(token == address(this), "ERC20FlashMint: Unsupported token");
        return
            amount > FLASH_FEE_MIN_THRESHOLD
                ? (amount * FLASH_FEE_BASIS_POINTS) / 10000
                : FLASH_FEE_MIN; // 0.01% fee or min
    }

    // --------------------------------------------
    // Modifier to check if mining is allowed
    // --------------------------------------------
    modifier onlyAllowedChain() {
        require(
            allowedChains[block.chainid],
            "Mining not allowed on this chain"
        );
        _;
    }

    /*
        ---------------------------------------------------------
        Proof-of-Work Minting
        ---------------------------------------------------------
    */

    /**
     * @notice Mints tokens to the caller using Proof-of-Work
     * @param nonce The solution nonce that satisfies the PoW requirement
     * @return success True if minting was successful
     * @dev Implements EIP-918 standard mint function
     * @dev The second parameter (bytes32) is unused but kept for EIP-918 compatibility
     * @dev The PoW algorithm: keccak256(challengeNumber, msg.sender, nonce) must be <= miningTarget
     * @dev Example: Miners find a nonce such that the hash digest is below the current target
     */
    function mint(
        uint256 nonce,
        bytes32
    ) external onlyAllowedChain returns (bool success) {
        require(
            block.timestamp >= miningStartTimestamp,
            "Mining not started yet"
        );
        return mintTo(nonce, msg.sender);
    }

    /**
     * @notice Mints tokens to a specified address using Proof-of-Work with weighted RNG
     * @param nonce The solution nonce that satisfies the PoW requirement
     * @param minter The address that will receive the mining reward
     * @return success True if minting was successful
     * @dev Implements the core PoW mining logic with Discordian-weighted rewards
     * @dev PoW Algorithm:
     *      1. Calculate digest = keccak256(challengeNumber, minter, nonce)
     *      2. Require uint256(digest) <= miningTarget (proof of work)
     *      3. Require no other reward in this block (one reward per block)
     *      4. Calculate weighted RNG tier based on historical blocks
     *      5. Mint tier-adjusted reward tokens to minter
     *      6. Start new mining epoch (update challenge, adjust difficulty if needed)
     * @dev The challengeNumber is updated after each successful mint to prevent pre-mining
     * @dev Difficulty adjusts every 23 epochs (Discordian retarget period)
     */
    function mintTo(
        uint256 nonce,
        address minter
    ) public onlyAllowedChain returns (bool success) {
        require(
            block.timestamp >= miningStartTimestamp,
            "Mining not started yet"
        );

        // PoW requirement: digest = keccak256(challengeNumber, minter, nonce)
        // Note: Built-in overflow protection in Solidity 0.8.28 will automatically
        // revert if totalSupply() + reward would overflow
        bytes32 digest = keccak256(
            abi.encodePacked(challengeNumber, minter, nonce)
        );
        require(uint256(digest) <= miningTarget, "Digest exceeds target");
        require(
            lastRewardEthBlockNumber != block.number,
            "Already rewarded in this block"
        );

        // Calculate weighted RNG tier using the PoW digest (unpredictable by miner)
        RewardTier tier = _calculateRewardTier(minter, digest);
        
        // Calculate tier-adjusted reward
        uint256 baseReward = BASE_REWARD_RATE * 10 ** decimals();
        uint256 tierMultiplier = _getTierMultiplier(tier);
        uint256 reward = (baseReward * tierMultiplier) / 10; // Divide by 10 since multipliers are stored as 10x

        _mint(minter, reward);
        tokensMinted += reward;

        // Update miner stats (tier counts and score)
        _updateMinerStats(minter, tier);

        lastRewardTo = minter;
        lastRewardAmount = reward;
        lastRewardEthBlockNumber = block.number;

        _startNewMiningEpoch();
        emit Mint(minter, reward, epochCount, challengeNumber);
        
        // Emit tier-specific event
        _emitTierEvent(minter, reward, tier);
        
        return true;
    }

    /**
     * @notice Calculates the reward tier using weighted RNG based on unpredictable sources
     * @param minter The address of the miner
     * @param powDigest The PoW digest (keccak256(challengeNumber, minter, nonce))
     * @return tier The determined reward tier
     * @dev Uses the PoW digest and block-level entropy that miners cannot predict/control
     * @dev CRITICAL: Does NOT use nonce directly - miners cannot game by trying different nonces
     * @dev Distribution (23-based Discordian system):
     *      - Enigma23: roll == 0 (1/23 ≈ 4.35%) - 23× multiplier
     *      - Blessed: roll == 1 || roll == 2 (2/23 ≈ 8.70%) - 5× multiplier
     *      - Favored: roll >= 3 && roll <= 5 (3/23 ≈ 13.04%) - 2.3× multiplier
     *      - Neutral: roll >= 6 && roll <= 12 (7/23 ≈ 30.43%) - 1.0× multiplier
     *      - Discordant: roll >= 13 (10/23 ≈ 43.48%) - 0.5× multiplier
     * @dev Total: 1 + 2 + 3 + 7 + 10 = 23 (perfect Discordian distribution)
     * @dev Security: Uses PoW digest (unpredictable), block.timestamp (minimal manipulation window),
     *      and historical blocks to prevent gaming. Does NOT use block.prevrandao to avoid validator manipulation.
     */
    function _calculateRewardTier(
        address minter,
        bytes32 powDigest
    ) internal view returns (RewardTier tier) {
        // Use historical blocks for entropy (safe, deterministic)
        // blockhash(block.number - 1) is always available
        // blockhash(block.number - 23) requires archive node if block.number < 23
        bytes32 blockHash1 = blockhash(block.number - 1);
        bytes32 blockHash23 = block.number >= 23 
            ? blockhash(block.number - 23) 
            : blockhash(block.number - 1); // Fallback if not enough history
        
        // Generate entropy from sources that miners cannot predict/control:
        // 1. powDigest - The PoW solution hash (unpredictable, miner must find valid nonce)
        // 2. block.timestamp - Only manipulable within ~1-2 second window
        // 3. Historical block hashes - Immutable once mined
        // 4. minter address - Fixed
        // NOTE: We do NOT use nonce directly - that would allow gaming!
        // NOTE: We do NOT use block.prevrandao - validators can manipulate it by withholding blocks
        uint256 entropy = uint256(
            keccak256(
                abi.encodePacked(
                    powDigest,              // PoW solution (unpredictable)
                    blockHash1,             // Previous block (known but immutable)
                    blockHash23,            // Historical block (known but immutable)
                    block.timestamp,        // Current timestamp (minimal manipulation)
                    minter                  // Miner address (fixed)
                )
            )
        );
        
        // Roll using 23-based system
        uint256 roll = entropy % 23;
        
        // Tier mapping (23-based Discordian distribution)
        if (roll == 0) {
            return RewardTier.Enigma23;      // 1/23 ≈ 4.35% - The rare 23 Enigma
        } else if (roll <= 2) {
            return RewardTier.Blessed;        // 2/23 ≈ 8.70% - Blessed of Eris
        } else if (roll <= 5) {
            return RewardTier.Favored;        // 3/23 ≈ 13.04% - Favored by Eris
        } else if (roll <= 12) {
            return RewardTier.Neutral;        // 7/23 ≈ 30.43% - Neutral outcome
        } else {
            return RewardTier.Discordant;     // 10/23 ≈ 43.48% - Discordant chaos
        }
    }

    /**
     * @notice Returns the multiplier for a given reward tier
     * @param tier The reward tier
     * @return multiplier The tier multiplier (stored as 10x, e.g., 23 = 2.3×)
     */
    function _getTierMultiplier(RewardTier tier) internal pure returns (uint256 multiplier) {
        if (tier == RewardTier.Discordant) {
            return TIER_DISCORDANT_MULTIPLIER;  // 0.5×
        } else if (tier == RewardTier.Neutral) {
            return TIER_NEUTRAL_MULTIPLIER;      // 1.0×
        } else if (tier == RewardTier.Favored) {
            return TIER_FAVORED_MULTIPLIER;     // 2.3×
        } else if (tier == RewardTier.Blessed) {
            return TIER_BLESSED_MULTIPLIER;     // 5×
        } else { // Enigma23
            return TIER_ENIGMA_MULTIPLIER;      // 23×
        }
    }

    /**
     * @notice Emits the appropriate tier-specific event
     * @param minter The address of the miner
     * @param reward The reward amount
     * @param tier The reward tier
     */
    function _emitTierEvent(address minter, uint256 reward, RewardTier tier) internal {
        if (tier == RewardTier.Discordant) {
            emit DiscordantMine(minter, reward);
        } else if (tier == RewardTier.Neutral) {
            emit NeutralMine(minter, reward);
        } else if (tier == RewardTier.Favored) {
            emit ErisFavor(minter, reward);
        } else if (tier == RewardTier.Blessed) {
            emit DiscordianBlessing(minter, reward);
        } else { // Enigma23
            emit Enigma23(minter, reward);
        }
    }

    /**
     * @notice Updates miner stats when a successful mine occurs
     * @param minter The address of the miner
     * @param tier The reward tier that was mined
     * @dev Increments the appropriate tier count and updates the total score
     * @dev Score calculation: Tier 1 = 1 point, Tier 2 = 2 points, Tier 3 = 3 points, Tier 4 = 4 points, Tier 5 = 5 points
     */
    function _updateMinerStats(
        address minter,
        RewardTier tier
    ) internal {
        // Register miner if this is their first mine
        if (!isRegisteredMiner[minter]) {
            miners.push(minter);
            isRegisteredMiner[minter] = true;
        }

        MinerStats storage stats = minerStats[minter];
        uint256 tierNumber;
        uint128 points;

        // Map RewardTier enum to tier number (1-5) and points
        if (tier == RewardTier.Discordant) {
            require(stats.tier1Count < MAX_TIER_COUNT, "Tier1 count overflow");
            stats.tier1Count++;
            tierNumber = 1;
            points = 1;
        } else if (tier == RewardTier.Neutral) {
            require(stats.tier2Count < MAX_TIER_COUNT, "Tier2 count overflow");
            stats.tier2Count++;
            tierNumber = 2;
            points = 2;
        } else if (tier == RewardTier.Favored) {
            require(stats.tier3Count < MAX_TIER_COUNT, "Tier3 count overflow");
            stats.tier3Count++;
            tierNumber = 3;
            points = 3;
        } else if (tier == RewardTier.Blessed) {
            require(stats.tier4Count < MAX_TIER_COUNT, "Tier4 count overflow");
            stats.tier4Count++;
            tierNumber = 4;
            points = 4;
        } else {
            // Enigma23
            require(stats.tier5Count < MAX_TIER_COUNT, "Tier5 count overflow");
            stats.tier5Count++;
            tierNumber = 5;
            points = 5;
        }

        // Update total score with overflow protection
        uint128 oldScore = stats.score;
        require(oldScore <= MAX_SCORE - points, "Score overflow");
        stats.score = oldScore + points;

        // Update leaderboard if score changed
        _updateLeaderboard(minter, oldScore, stats.score);

        // Emit optimized event (only changed tier and new score)
        emit MinerStatsUpdated(
            minter,
            tierNumber,
            stats.score
        );
    }

    /**
     * @notice Updates the sorted leaderboard when a miner's score changes
     * @param miner The address of the miner
     * @param oldScore The miner's score before the update
     * @param newScore The miner's score after the update
     * @dev Maintains a sorted leaderboard array (highest score first)
     * @dev Only maintains top MAX_LEADERBOARD_SIZE miners to keep gas costs reasonable
     */
    function _updateLeaderboard(
        address miner,
        uint128 oldScore,
        uint128 newScore
    ) internal {
        uint256 currentIndex = leaderboardIndex[miner];
        bool isInLeaderboard = currentIndex > 0;

        // If miner is already in leaderboard
        if (isInLeaderboard) {
            uint256 arrayIndex = currentIndex - 1; // Convert to 0-indexed
            
            // If score increased, move miner up in leaderboard
            if (newScore > oldScore) {
                // Remove from current position
                _removeFromLeaderboard(arrayIndex);
                
                // Find new position (higher scores first)
                uint256 newPosition = _findLeaderboardPosition(newScore);
                _insertIntoLeaderboard(miner, newPosition);
            }
            // If score didn't change, no update needed
            // Note: Scores can only increase, so we don't need to handle decreases
        } else {
            // Miner not in leaderboard - check if they should be added
            if (leaderboard.length < MAX_LEADERBOARD_SIZE) {
                // Leaderboard not full, add miner
                uint256 position = _findLeaderboardPosition(newScore);
                _insertIntoLeaderboard(miner, position);
            } else {
                // Leaderboard is full - check if new score beats the lowest score
                uint128 lowestScore = minerStats[leaderboard[leaderboard.length - 1]].score;
                if (newScore > lowestScore) {
                    // Remove lowest scorer
                    _removeFromLeaderboard(leaderboard.length - 1);
                    
                    // Add new miner
                    uint256 position = _findLeaderboardPosition(newScore);
                    _insertIntoLeaderboard(miner, position);
                }
            }
        }
    }

    /**
     * @notice Finds the correct position in leaderboard for a given score
     * @param score The score to find position for
     * @return position The index where this score should be inserted (0-indexed)
     * @dev Uses binary search for efficiency
     */
    function _findLeaderboardPosition(uint128 score) internal view returns (uint256 position) {
        uint256 left = 0;
        uint256 right = leaderboard.length;
        
        // Binary search for insertion point (maintains descending order)
        while (left < right) {
            uint256 mid = (left + right) / 2;
            uint128 midScore = minerStats[leaderboard[mid]].score;
            
            if (score > midScore) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }
        
        return left;
    }

    /**
     * @notice Inserts a miner into the leaderboard at the specified position
     * @param miner The address of the miner to insert
     * @param position The position to insert at (0-indexed)
     */
    function _insertIntoLeaderboard(address miner, uint256 position) internal {
        // Shift elements to the right
        leaderboard.push(address(0)); // Add placeholder
        for (uint256 i = leaderboard.length - 1; i > position; i--) {
            leaderboard[i] = leaderboard[i - 1];
            leaderboardIndex[leaderboard[i]] = i + 1; // Update index (1-indexed)
        }
        
        // Insert miner
        leaderboard[position] = miner;
        leaderboardIndex[miner] = position + 1; // Store as 1-indexed
    }

    /**
     * @notice Removes a miner from the leaderboard at the specified position
     * @param position The position to remove from (0-indexed)
     */
    function _removeFromLeaderboard(uint256 position) internal {
        address removedMiner = leaderboard[position];
        leaderboardIndex[removedMiner] = 0; // Mark as not in leaderboard
        
        // Shift elements to the left
        for (uint256 i = position; i < leaderboard.length - 1; i++) {
            leaderboard[i] = leaderboard[i + 1];
            leaderboardIndex[leaderboard[i]] = i + 1; // Update index (1-indexed)
        }
        
        // Remove last element
        leaderboard.pop();
    }

    /**
     * @notice Starts a new mining epoch after a successful mint
     * @dev Called internally after each successful PoW solution
     * @dev Updates epoch count, adjusts difficulty if needed, and generates new challenge
     * @dev Difficulty adjustment occurs every _BLOCKS_PER_READJUSTMENT (23) epochs (Discordian retarget)
     * @dev Challenge number is set to blockhash(block.number - 1) per EIP-918 standard
     */
    function _startNewMiningEpoch() internal {
        if (epochCount >= MAX_LIMIT) {
            epochCount = 0; // Reset epochCount to zero
        } else {
            epochCount++; // Increment epochCount
        }

        // Difficulty readjustment
        if (epochCount % _BLOCKS_PER_READJUSTMENT == 0) {
            uint ethBlocksSinceLastDifficultyPeriod = block.number -
                latestDifficultyPeriodStarted;
            _reAdjustDifficulty(ethBlocksSinceLastDifficultyPeriod);
        }

        // New challenge number
        challengeNumber = blockhash(block.number - 1);
        emit NewEpochStarted(epochCount, challengeNumber);
    }

    /**
     * @notice Adjusts mining difficulty based on actual vs target block time
     * @param ethBlocksSinceLastDifficultyPeriod Number of Ethereum blocks since last adjustment
     * @dev Difficulty Adjustment Algorithm:
     *      - Target: _BLOCKS_PER_READJUSTMENT (23) * 60 Ethereum blocks per adjustment period
     *      - If blocks mined too fast (fewer blocks than target):
     *        * Increase difficulty by decreasing miningTarget
     *        * Adjustment = (miningTarget / _ADJUSTMENT_DIVISOR) * excess_percentage
     *        * Maximum adjustment capped at _MAX_EXCESS_BLOCK_PCT_EXTRA (1000%)
     *      - If blocks mined too slow (more blocks than target):
     *        * Decrease difficulty by increasing miningTarget
     *        * Adjustment = (miningTarget / _ADJUSTMENT_DIVISOR) * shortage_percentage
     *        * Maximum adjustment capped at _MAX_SHORTAGE_BLOCK_PCT_EXTRA (2000%)
     *        * Extended inactivity (>10x target): Additional adjustment applied
     *      - miningTarget is bounded between _MINIMUM_TARGET and _MAXIMUM_TARGET
     * @dev The adjustment divisor (20000) makes adjustments 10x gentler than typical implementations
     * @dev This prevents wild swings in difficulty and maintains stable mining rates
     */
    function _reAdjustDifficulty(
        uint ethBlocksSinceLastDifficultyPeriod
    ) internal {
        uint targetEthBlocksPerDiffPeriod = _BLOCKS_PER_READJUSTMENT *
            _TARGET_BLOCKS_MULTIPLIER;

        if (ethBlocksSinceLastDifficultyPeriod < targetEthBlocksPerDiffPeriod) {
            // Blocks mined too fast - increase difficulty (decrease target)
            uint excess_block_pct = (targetEthBlocksPerDiffPeriod *
                _PERCENTAGE_BASE) / ethBlocksSinceLastDifficultyPeriod;
            uint excess_block_pct_extra = (excess_block_pct - _PERCENTAGE_BASE)
                .limitLessThan(_MAX_EXCESS_BLOCK_PCT_EXTRA);

            // Calculate adjustment amount with bounds checking to prevent underflow
            uint adjustmentAmount = (miningTarget / _ADJUSTMENT_DIVISOR) *
                excess_block_pct_extra;
            // Ensure we don't decrease below minimum target
            if (
                miningTarget > adjustmentAmount &&
                miningTarget - adjustmentAmount >= _MINIMUM_TARGET
            ) {
                miningTarget = miningTarget - adjustmentAmount;
            } else {
                // If adjustment would go below minimum, set to minimum
                miningTarget = _MINIMUM_TARGET;
            }
        } else {
            // Blocks mined too slow - decrease difficulty (increase target)
            uint shortage_block_pct = (ethBlocksSinceLastDifficultyPeriod *
                _PERCENTAGE_BASE) / targetEthBlocksPerDiffPeriod;
            // Allow larger downward adjustments (up to _MAX_SHORTAGE_BLOCK_PCT_EXTRA)
            // to handle long periods of inactivity more effectively
            uint shortage_block_pct_extra = (shortage_block_pct -
                _PERCENTAGE_BASE).limitLessThan(_MAX_SHORTAGE_BLOCK_PCT_EXTRA);

            // Calculate base adjustment amount
            uint baseAdjustment = (miningTarget / _ADJUSTMENT_DIVISOR) *
                shortage_block_pct_extra;

            // For very long gaps, apply a more aggressive downward adjustment
            // If gap is more than _EXTENDED_INACTIVITY_THRESHOLD times the target, use a larger adjustment
            uint additionalAdjustment = 0;
            if (
                ethBlocksSinceLastDifficultyPeriod >
                targetEthBlocksPerDiffPeriod * _EXTENDED_INACTIVITY_THRESHOLD
            ) {
                // Apply additional downward adjustment for extended inactivity
                additionalAdjustment =
                    (miningTarget / _ADJUSTMENT_DIVISOR) *
                    _EXTENDED_INACTIVITY_ADJUSTMENT;
            }

            // Calculate total adjustment with bounds checking to prevent overflow
            uint totalAdjustment = baseAdjustment + additionalAdjustment;
            // Ensure we don't increase above maximum target
            if (miningTarget <= _MAXIMUM_TARGET - totalAdjustment) {
                miningTarget = miningTarget + totalAdjustment;
            } else {
                // If adjustment would exceed maximum, set to maximum
                miningTarget = _MAXIMUM_TARGET;
            }
        }

        latestDifficultyPeriodStarted = block.number;

        // Final bounds check (defensive programming - should already be within bounds)
        if (miningTarget < _MINIMUM_TARGET) {
            miningTarget = _MINIMUM_TARGET;
        }
        if (miningTarget > _MAXIMUM_TARGET) {
            miningTarget = _MAXIMUM_TARGET;
        }

        emit DifficultyAdjusted(
            miningTarget,
            (_MAXIMUM_TARGET / miningTarget),
            ethBlocksSinceLastDifficultyPeriod
        );
    }

    /*
        ---------------------------------------------------------
        Admin Management
        ---------------------------------------------------------
    */

    /**
     * @notice Sets the authorized admin address that can manage chains and CCIP settings
     * @param _admin The address authorized to manage chains and CCIP settings
     * @dev Can be called to set the authorized address
     * @dev Can be updated by:
     *      - Current admin (if already set)
     *      - Anyone if admin is address(0) (not yet set)
     *      - Anyone if admin is placeholder address (0x1111...)
     * @dev Emits AdminUpdated event
     * @dev This is a non-critical admin function for operational parameters
     */
    function setAdmin(
        address _admin
    ) external {
        require(
            _admin != address(0),
            "Cannot set to zero address"
        );
        // Allow setting if not set yet (address(0)), or if current admin is placeholder, or allow current admin to update
        address placeholder = address(
            0x1111111111111111111111111111111111111111
        );
        require(
            admin == address(0) ||
                admin == placeholder ||
                msg.sender == admin,
            "Unauthorized to set admin"
        );
        address oldAdmin = admin;
        admin = _admin;
        emit AdminUpdated(oldAdmin, _admin);
    }

    /*
        ---------------------------------------------------------
        Public Getters (Difficulty, Targets, Supply, etc.)
        ---------------------------------------------------------
    */
    /**
     * @notice Returns the adjustment interval in seconds
     * @return The adjustment interval in seconds
     * @dev Required by EIP-918 standard
     * @dev Calculated as: 23 epochs * 60 Ethereum blocks per epoch * 12 seconds per block
     * @dev This represents the target time between difficulty adjustments
     */
    function getAdjustmentInterval() external pure returns (uint) {
        // 23 epochs * 60 blocks per epoch * 12 seconds per block = 16,560 seconds
        return _BLOCKS_PER_READJUSTMENT * _TARGET_BLOCKS_MULTIPLIER * 12;
    }

    /**
     * @notice Returns the current PoW challenge number
     * @return The current challenge number (bytes32)
     * @dev Required by EIP-918 standard
     * @dev Challenge number is updated after each successful mint using blockhash(block.number - 1)
     * @dev Miners use this with their address and nonce to find valid solutions
     */
    function getChallengeNumber() external view returns (bytes32) {
        return challengeNumber;
    }

    /**
     * @notice Returns the current mining difficulty
     * @return The current difficulty (higher = more difficult)
     * @dev Required by EIP-918 standard
     * @dev Difficulty = _MAXIMUM_TARGET / miningTarget
     * @dev Higher difficulty means lower miningTarget, making it harder to find valid solutions
     */
    function getMiningDifficulty() external view returns (uint) {
        return _MAXIMUM_TARGET / miningTarget;
    }

    /**
     * @notice Returns the current mining target
     * @return The current mining target (lower = more difficult)
     * @dev Required by EIP-918 standard
     * @dev A valid PoW solution must have keccak256(challengeNumber, minter, nonce) <= miningTarget
     * @dev Target is adjusted periodically based on actual vs target block time
     */
    function getMiningTarget() external view returns (uint) {
        return miningTarget;
    }

    /**
     * @notice Returns the current mining reward amount
     * @dev Required by EIP-918 standard
     * @return The current mining reward in wei
     */
    function getMiningReward() external view returns (uint) {
        return currentMiningReward;
    }

    /**
     * @notice Returns the total amount of tokens minted via PoW mining
     * @return The cumulative amount of tokens minted through mining
     * @dev This tracks only PoW-minted tokens, not cross-chain mints or other sources
     * @dev Useful for tracking mining progress and total supply from mining
     */
    function minedSupply() external view returns (uint) {
        return tokensMinted;
    }

    /*
        ---------------------------------------------------------
        Miner Stats & Leaderboard Getters
        ---------------------------------------------------------
    */

    /**
     * @notice Returns the complete stats for a given miner
     * @param miner The address of the miner
     * @return tier1Count Number of Tier 1 (Discordant) mines
     * @return tier2Count Number of Tier 2 (Neutral) mines
     * @return tier3Count Number of Tier 3 (Favored) mines
     * @return tier4Count Number of Tier 4 (Blessed) mines
     * @return tier5Count Number of Tier 5 (Enigma23) mines
     * @return score Total score (tier1*1 + tier2*2 + tier3*3 + tier4*4 + tier5*5)
     * @dev Use this function to retrieve all stats for a miner in a single call
     * @dev IMPORTANT: Works for ALL miners, not just those in the top 100 leaderboard
     * @dev The minerStats mapping tracks stats for every miner who has ever mined
     * @dev Perfect for trophy crafting and checking stats for any miner address
     */
    function getMinerStats(
        address miner
    )
        external
        view
        returns (
            uint128 tier1Count,
            uint128 tier2Count,
            uint128 tier3Count,
            uint128 tier4Count,
            uint128 tier5Count,
            uint128 score
        )
    {
        MinerStats memory stats = minerStats[miner];
        return (
            stats.tier1Count,
            stats.tier2Count,
            stats.tier3Count,
            stats.tier4Count,
            stats.tier5Count,
            stats.score
        );
    }

    /**
     * @notice Returns the score for a given miner
     * @param miner The address of the miner
     * @return score Total score (tier1*1 + tier2*2 + tier3*3 + tier4*4 + tier5*5)
     * @dev Lightweight function to get just the score
     * @dev IMPORTANT: Works for ALL miners, not just those in the top 100 leaderboard
     * @dev Returns 0 if the miner has never mined (no stats recorded)
     */
    function getMinerScore(address miner) external view returns (uint128 score) {
        return minerStats[miner].score;
    }

    /**
     * @notice Returns the total number of miners
     * @return count Total number of unique miners
     * @dev Use this with getMinerStatsBatch to retrieve all miner data
     */
    function getMinerCount() external view returns (uint256 count) {
        return miners.length;
    }

    /**
     * @notice Returns miner addresses in a batch (for pagination)
     * @param offset Starting index in the miners array
     * @param limit Maximum number of addresses to return
     * @return minerAddresses Array of miner addresses
     * @return totalCount Total number of miners (for pagination)
     * @dev Use this to paginate through all miners. Example: getMinerAddressesBatch(0, 100) gets first 100 miners
     * @dev Then call getMinerStatsBatch with those addresses to get their stats
     */
    function getMinerAddressesBatch(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory minerAddresses, uint256 totalCount) {
        totalCount = miners.length;
        uint256 end = offset + limit;
        if (end > totalCount) {
            end = totalCount;
        }
        if (offset >= totalCount) {
            return (new address[](0), totalCount);
        }

        uint256 length = end - offset;
        minerAddresses = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            minerAddresses[i] = miners[offset + i];
        }
        return (minerAddresses, totalCount);
    }

    /**
     * @notice Returns stats for multiple miners in a single call
     * @param minerAddresses Array of miner addresses to query
     * @return stats Array of MinerStats structs corresponding to the input addresses
     * @dev Use this with getMinerAddressesBatch to efficiently retrieve all miner stats
     * @dev Example: Get addresses with getMinerAddressesBatch(0, 100), then get stats with getMinerStatsBatch(addresses)
     */
    function getMinerStatsBatch(
        address[] calldata minerAddresses
    ) external view returns (MinerStats[] memory stats) {
        stats = new MinerStats[](minerAddresses.length);
        for (uint256 i = 0; i < minerAddresses.length; i++) {
            stats[i] = minerStats[minerAddresses[i]];
        }
        return stats;
    }

    /**
     * @notice Returns the sorted leaderboard (top miners by score)
     * @param limit Maximum number of top miners to return
     * @return topMiners Array of miner addresses sorted by score (highest first)
     * @return scores Array of scores corresponding to the miners
     * @dev Returns the top N miners from the maintained sorted leaderboard
     * @dev This is gas-efficient as it only reads from a pre-sorted array
     */
    function getLeaderboard(
        uint256 limit
    ) external view returns (address[] memory topMiners, uint128[] memory scores) {
        uint256 length = leaderboard.length < limit ? leaderboard.length : limit;
        topMiners = new address[](length);
        scores = new uint128[](length);
        
        for (uint256 i = 0; i < length; i++) {
            topMiners[i] = leaderboard[i];
            scores[i] = minerStats[leaderboard[i]].score;
        }
        
        return (topMiners, scores);
    }

    /**
     * @notice Returns the leaderboard with full stats
     * @param limit Maximum number of top miners to return
     * @return topMiners Array of miner addresses sorted by score (highest first)
     * @return stats Array of MinerStats for the top miners
     * @dev Returns complete stats for the top N miners
     */
    function getLeaderboardWithStats(
        uint256 limit
    ) external view returns (address[] memory topMiners, MinerStats[] memory stats) {
        uint256 length = leaderboard.length < limit ? leaderboard.length : limit;
        topMiners = new address[](length);
        stats = new MinerStats[](length);
        
        for (uint256 i = 0; i < length; i++) {
            topMiners[i] = leaderboard[i];
            stats[i] = minerStats[leaderboard[i]];
        }
        
        return (topMiners, stats);
    }

    /**
     * @notice Returns the current size of the leaderboard
     * @return size Number of miners currently in the leaderboard
     */
    function getLeaderboardSize() external view returns (uint256 size) {
        return leaderboard.length;
    }

    /*
        ---------------------------------------------------------
        Faucet
        ---------------------------------------------------------
    */
    function faucetMint() external returns (bool success) {
        require(
            block.timestamp >= lastFaucetClaim[msg.sender] + faucetCooldown,
            "Faucet: cooldown period not met"
        );
        _mint(msg.sender, faucetAmount);
        lastFaucetClaim[msg.sender] = block.timestamp;
        return true;
    }

    /*
        ---------------------------------------------------------
        Fallback: Reject ETH
        ---------------------------------------------------------
    */
    receive() external payable {
        revert("No direct ETH deposits");
    }
}
