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

// OP Superchain libraries
import {IERC7802} from "./libs/IERC7802.sol";
// Import IERC165 from same path as CCIPReceiver to avoid conflicts
import {IERC165 as IERC165CCIP} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Predeploys} from "./libs/Predeploys.sol";
import {Unauthorized} from "./libs/CommonErrors.sol";

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
    Eris Token with PoW, Difficulty Adjustment and Superchain
    ---------------------------------------------------------
*/
contract ERIS is
    ERC20,
    ERC20Permit,
    ERC20Burnable,
    ERC20FlashMint,
    IERC7802,
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
    uint public rewardEra; // Tracks how many halvings have happened
    uint public currentMiningReward;
    uint public tokensMinted;

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
            0xcac64DA6455345C0b7d8b9746e3F15df133A01f6
        );

        // Initialize CCIP extraArgs with default values
        ccipGasLimit = 200_000; // Default gas limit for CCIP message execution
        ccipAllowOutOfOrderExecution = true; // Default: allow out-of-order execution

        miningTarget = _MAXIMUM_TARGET;
        latestDifficultyPeriodStarted = block.number;
        challengeNumber = blockhash(block.number - 1);

        // Initialize allowed chains (example: 1 for Ethereum mainnet, 2 for Binance Smart Chain)
        allowedChains[8453] = true; // Coinbase Base
        allowedChains[42161] = true; // Arbitrum One Mainnet
        allowedChains[137] = true; // Polygon (MATIC) Mainnet
        allowedChains[56] = true; // BNB Mainnet
        allowedChains[57073] = true; // Ink Mainnet
        allowedChains[130] = true; // Unichain Mainnet
        allowedChains[480] = true; // World Chain Mainnet
        allowedChains[1868] = true; // Soneium Mainnet
        allowedChains[1] = true; // ETH Mainnet
        // Add more chains as needed

        // Initialize allowed destination chains using CCIP chain selectors
        // Chain selectors are from Chainlink CCIP Directory:
        // Mainnet: https://docs.chain.link/ccip/directory/mainnet
        // Testnet: https://docs.chain.link/ccip/directory/testnet
        // Base
        uint64 baseSelector = 15971525489660198786;
        allowedDestinationChains[baseSelector] = true;
        chainNames[baseSelector] = "Base";
        chainSelectorsByName["Base"] = baseSelector;

        // BNB Chain
        uint64 bnbSelector = 11344663589394136015;
        allowedDestinationChains[bnbSelector] = true;
        chainNames[bnbSelector] = "BNB";
        chainSelectorsByName["BNB"] = bnbSelector;

        // Arbitrum One
        uint64 arbitrumSelector = 4949039107694359620;
        allowedDestinationChains[arbitrumSelector] = true;
        chainNames[arbitrumSelector] = "Arbitrum One";
        chainSelectorsByName["Arbitrum One"] = arbitrumSelector;

        // Ink
        uint64 inkSelector = 3461204551265785888;
        allowedDestinationChains[inkSelector] = true;
        chainNames[inkSelector] = "Ink";
        chainSelectorsByName["Ink"] = inkSelector;

        // Ethereum Mainnet
        uint64 ethereumSelector = 5009297550715157269;
        allowedDestinationChains[ethereumSelector] = true;
        chainNames[ethereumSelector] = "Ethereum";
        chainSelectorsByName["Ethereum"] = ethereumSelector;

        // Polygon
        uint64 polygonSelector = 4051577828743386545;
        allowedDestinationChains[polygonSelector] = true;
        chainNames[polygonSelector] = "Polygon";
        chainSelectorsByName["Polygon"] = polygonSelector;

        // Unichain
        uint64 unichainSelector = 1923510103922296319;
        allowedDestinationChains[unichainSelector] = true;
        chainNames[unichainSelector] = "Unichain";
        chainSelectorsByName["Unichain"] = unichainSelector;

        // Soneium
        uint64 soneiumSelector = 12505351618335765396;
        allowedDestinationChains[soneiumSelector] = true;
        chainNames[soneiumSelector] = "Soneium";
        chainSelectorsByName["Soneium"] = soneiumSelector;

        // World Chain
        uint64 worldChainSelector = 2049429975587534727;
        allowedDestinationChains[worldChainSelector] = true;
        chainNames[worldChainSelector] = "World Chain";
        chainSelectorsByName["World Chain"] = worldChainSelector;

        miningStartTimestamp = 1764309600; // Set the mining start timestamp
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
        if (chainId == 1)
            return address(0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D); // Ethereum
        if (chainId == 8453)
            return address(0x881e3A65B4d4a04dD529061dd0071cf975F58bCD); // Base
        if (chainId == 137)
            return address(0x849c5ED5a80F5B408Dd4969b78c2C8fdf0565Bfe); // Polygon
        if (chainId == 56)
            return address(0x34B03Cb9086d7D758AC55af71584F81A598759FE); // BNB
        if (chainId == 57073)
            return address(0xca7c90A52B44E301AC01Cb5EB99b2fD99339433A); // Ink
        if (chainId == 42161)
            return address(0x141fa059441E0ca23ce184B6A78bafD2A517DdE8); // Arbitrum One
        if (chainId == 480)
            return address(0x5fd9E4986187c56826A3064954Cfa2Cf250cfA0f); // World Chain
        if (chainId == 1868)
            return address(0x8C8B88d827Fe14Df2bc6392947d513C86afD6977); // Soneium
        if (chainId == 130)
            return address(0x68891f5F96695ECd7dEdBE2289D1b73426ae7864); // Unichain
        return address(0);
    }

    /*
        ---------------------------------------------------------
        Chainlink CCIP Implementation
        ---------------------------------------------------------
    */

    /**
     * @notice Initiates a Cross-Chain Bridge Transaction using Chainlink CCIP
     * @param destinationChainName Human-readable name of the destination chain (e.g., "Base", "Ethereum", "Polygon")
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
     * @param destinationChainName Human-readable name of the destination chain (e.g., "Base", "Ethereum", "Polygon")
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
        Superchain
        ---------------------------------------------------------
    */
    /// @notice Allows the SuperchainTokenBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function crosschainMint(address _to, uint256 _amount) external {
        // Only the `SuperchainTokenBridge` has permissions to mint tokens during crosschain transfers.
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE)
            revert Unauthorized();

        // Mint tokens to the `_to` account's balance.
        _mint(_to, _amount);

        // Emit the CrosschainMint event included on IERC7802 for tracking token mints
        emit CrosschainMint(_to, _amount, msg.sender);
    }

    /// @notice Allows the SuperchainTokenBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function crosschainBurn(address _from, uint256 _amount) external {
        // Only the `SuperchainTokenBridge` has permissions to burn tokens during crosschain transfers.
        if (msg.sender != Predeploys.SUPERCHAIN_TOKEN_BRIDGE)
            revert Unauthorized();

        // Burn the tokens from the `_from` account's balance.
        _burn(_from, _amount);

        // Emit the CrosschainBurn event included on IERC7802 for tracking token burns
        emit CrosschainBurn(_from, _amount, msg.sender);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 _interfaceId
    ) public pure virtual override(CCIPReceiver, IERC165CCIP) returns (bool) {
        return
            _interfaceId == type(IERC7802).interfaceId ||
            _interfaceId == type(IERC20).interfaceId ||
            _interfaceId == type(IERC165CCIP).interfaceId ||
            CCIPReceiver.supportsInterface(_interfaceId);
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
