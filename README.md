# ERIS Token (Eris Token)

A Proof-of-Work (PoW) ERC-20 token with **Discordian-weighted RNG rewards**, adaptive difficulty adjustment, cross-chain bridging via Chainlink CCIP, and Superchain compatibility. Features a 23-based reward system with 5 tiers ranging from 11.5 ERIS (Discordant) to 529 ERIS (23 Enigma jackpot).

## Overview

ERIS is a mineable ERC-20 token that implements:
- **Proof-of-Work Mining**: EIP-918 compliant mining mechanism with weighted RNG rewards
- **Discordian Reward System**: 23-based weighted randomness with 5 reward tiers
- **Adaptive Difficulty Adjustment**: Gentle difficulty scaling that maintains stable emission rates
- **Cross-Chain Bridging**: Chainlink CCIP integration for seamless token transfers across chains
- **Superchain Support**: IERC7802 interface for OP Superchain compatibility
- **Flash Loans**: ERC-3156 Flash Mint support

**Token Supply**: ERIS has an **unlimited supply** design. Tokens are continuously minted through:
- Proof-of-Work mining (with Discordian-weighted rewards)
- Cross-chain bridging operations (CCIP and Superchain)
- Flash minting (temporary, must be repaid within transaction)

This design allows for continuous mining rewards and seamless cross-chain operations without supply constraints.

## Features

### Proof-of-Work Mining
- EIP-918 standard compliant
- Keccak256-based hashing algorithm
- One reward per Ethereum block
- Automatic challenge number updates

### Difficulty Adjustment
- **Adjustment Period**: Every 23 epochs (Discordian retarget period)
- **Target Block Time**: ~60 Ethereum blocks per epoch
- **Gentle Scaling**: 10× gentler than typical implementations (80× gentler than Bitcoin)
- **Maximum Adjustment**: ~5% per period (upward), ~12.5% per period (downward)
- **Extended Inactivity Recovery**: Additional adjustment mechanism for long inactivity periods

See [DIFFICULTY_SCALING_ANALYSIS.md](./DIFFICULTY_SCALING_ANALYSIS.md) for detailed analysis.

### Cross-Chain Bridging

#### Chainlink CCIP
- Burn-and-mint cross-chain transfers
- Supports multiple chains (Base, Ethereum, Polygon, BNB, Arbitrum, Ink, Unichain, Soneium, World Chain)
- Deterministic deployment for seamless bridging
- Configurable gas limits and execution options

#### Superchain (IERC7802)
- Native OP Superchain token bridge support
- Cross-chain minting and burning via SuperchainTokenBridge

### Discordian Weighted RNG Reward System

ERIS uses a **23-based weighted randomness system** inspired by Discordian philosophy and the 23 Enigma. Each successful PoW solution receives a reward tier determined by secure, unpredictable entropy sources.

#### Reward Tiers

| Tier | Name | Probability | Multiplier | Reward Amount |
|------|------|------------|------------|---------------|
| **I** | Discordant | 43.48% (10/23) | 0.5× | **11.5 ERIS** |
| **II** | Neutral | 30.43% (7/23) | 1.0× | **23 ERIS** |
| **III** | Favored | 13.04% (3/23) | 2.3× | **52.9 ERIS** |
| **IV** | Blessed of Eris | 8.70% (2/23) | 5× | **115 ERIS** |
| **V** | **23 Enigma** | 4.35% (1/23) | **23×** | **529 ERIS** |

**Base Reward**: 23 ERIS tokens per successful PoW solution

**Expected Value**: ~49.45 ERIS per successful mine (weighted average)

#### Reward Tier Descriptions

**Tier I - Discordant (11.5 ERIS)**
- **Probability**: 43.48% (10 out of 23)
- **Multiplier**: 0.5×
- **Reward**: 11.5 ERIS
- **Description**: The most common outcome, representing the chaotic nature of Discordianism. Miners receive half the base reward, reflecting the unpredictable and sometimes unfavorable aspects of the universe.

**Tier II - Neutral (23 ERIS)**
- **Probability**: 30.43% (7 out of 23)
- **Multiplier**: 1.0×
- **Reward**: 23 ERIS
- **Description**: The standard reward tier. Miners receive the full base reward of 23 ERIS, representing balance and neutrality in the Discordian cosmology.

**Tier III - Favored (52.9 ERIS)**
- **Probability**: 13.04% (3 out of 23)
- **Multiplier**: 2.3×
- **Reward**: 52.9 ERIS
- **Description**: A favorable outcome where miners receive 2.3× the base reward. This tier represents Eris showing favor to the miner, granting them a bonus reward for their efforts.

**Tier IV - Blessed of Eris (115 ERIS)**
- **Probability**: 8.70% (2 out of 23)
- **Multiplier**: 5×
- **Reward**: 115 ERIS
- **Description**: A rare blessing from Eris herself. Miners receive 5× the base reward, representing a significant blessing in the Discordian tradition. This tier is approximately twice as rare as the Favored tier.

**Tier V - 23 Enigma (529 ERIS)**
- **Probability**: 4.35% (1 out of 23)
- **Multiplier**: 23×
- **Reward**: 529 ERIS
- **Description**: The legendary 23 Enigma jackpot. This is the rarest tier, occurring exactly 1 in 23 times. Miners receive 23× the base reward (529 ERIS), representing the ultimate manifestation of the 23 Enigma in Discordian philosophy. This tier is the holy grail for miners, combining the sacred number 23 with maximum reward.

#### Security Features

- **Anti-Gaming Protection**: Uses PoW digest (unpredictable) instead of miner-controlled nonce
- **Multi-Source Entropy**: Combines PoW solution hash, historical blocks, block timestamp, and difficulty
- **Deterministic & Verifiable**: All entropy sources are on-chain and verifiable
- **No Manipulation**: Miners cannot predict or control tier outcomes before finding valid solutions

#### Tier Events

Each tier emits a unique event for tracking and analytics:
- `DiscordantMine` - Discordant tier rewards
- `NeutralMine` - Neutral tier rewards
- `ErisFavor` - Favored tier rewards
- `DiscordianBlessing` - Blessed tier rewards
- `Enigma23` - Rare 23 Enigma jackpot rewards

### Flash Loans
- ERC-3156 Flash Mint implementation
- 0.01% fee (or minimum 1,000 wei for small amounts)
- Useful for arbitrage and DeFi operations

## Contract Variants

- **ERIS.sol**: Main production contract with full feature set (Token: ERIS)
- **ERISSepolia.sol**: Sepolia testnet variant (Token: ERIS)
- **ERISTest.sol**: Test variant with additional features (Token: ERIS)

## Deployed Contracts

### Mainnet Contracts
- **ERIS (ERIS Token)**: `0xae80e9FF0e624C44C252aD950DbF39ac9BdB9E4f`

### Testnet Contracts
- **ERISSepolia (ERIS Token)**: `0xCeF263A2587fe8F9d4BEDAb339E4b5258ac07690`

> **Note on Deterministic Deployments**: These contracts use deterministic deployment (CREATE2), which means each contract uses the **same address on each supported chain**. This enables seamless cross-chain bridging and ensures consistent contract addresses across all networks where the contracts are deployed.
>
> **Security Requirement**: The contract enforces `sender == address(this)` in CCIP message validation. This security measure requires deterministic deployment using CREATE2 with identical salt and init code on all chains. Failure to deploy deterministically will result in rejected cross-chain messages.

## Supported Chains

### Mainnet Chains
- Base (8453)
- Ethereum Mainnet (1)
- Arbitrum One (42161)
- Polygon (137)
- BNB Chain (56)

### Testnet Chains
- Base Sepolia
- Arbitrum Sepolia
- Ethereum Sepolia

## Installation

```bash
npm install
```

## Configuration

Create a `.env` file with the following variables:

```env
PRIVATE_KEY=your_private_key_here
SALT=0x0000000000000000000000000000000000000000000000000000000000000000

# Optional: Unified Etherscan API key for contract verification
# Etherscan has unified their API, so a single key works across all supported chains
# Get your API key from https://etherscan.io/apis
ETHERSCAN_API_KEY=your_unified_api_key_here
```

See `.env.example` for a template.

## Building

```bash
npm run build
# or
npx hardhat compile
```

## Deployment

### Deploy ERIS (Mainnet)
```bash
npm run deploy_eris
# or
npx hardhat ignition deploy ignition/modules/ERIS.ts --network base --strategy create2
```

### Deploy ERISSepolia (Testnet)
```bash
npm run deploy_erisSep
# or
npx hardhat ignition deploy ignition/modules/ERISSepolia.ts --network base-sepolia --strategy create2
```

### Deploy ERISTest (Testnet)
```bash
npm run deploy_erisTest
# or
npx hardhat ignition deploy ignition/modules/ERISTest.ts --network arbitrum-sepolia --strategy create2
```

## Usage

### Mining (Proof-of-Work)

```solidity
// Mine tokens to your address
function mint(uint256 nonce, bytes32) external returns (bool);

// Mine tokens to a specific address
function mintTo(uint256 nonce, address minter) external returns (bool);
```

**PoW Algorithm**: Find a nonce such that:
```
keccak256(challengeNumber, minter, nonce) <= miningTarget
```

**Reward Calculation**: After finding a valid PoW solution:
1. PoW digest is calculated: `digest = keccak256(challengeNumber, minter, nonce)`
2. Reward tier is determined using weighted RNG based on:
   - PoW digest (unpredictable)
   - Historical block hashes (block.number - 1, block.number - 23)
   - Block timestamp and difficulty
   - Miner address
3. Final reward = Base Reward (23 ERIS) × Tier Multiplier

**Note**: The tier cannot be predicted or gamed - miners must find valid PoW solutions first, and the tier is determined by unpredictable entropy sources.

### Cross-Chain Bridging (CCIP)

```solidity
// Bridge tokens to another chain
function sendCCIPCrossChainBridge(
    string memory destinationChainName,
    uint256 amount
) external payable;

// Get fee estimate
function getCCIPCrossChainBridgeFee(
    string memory destinationChainName,
    uint256 amount
) external view returns (uint256 fee);
```

**Supported Chain Names**: "Base", "Ethereum", "Polygon", "BNB", "Arbitrum One"

#### CCIP Bridge Important Notes

**Refund Mechanism:**
- Excess ETH payments are automatically refunded using `transfer()` per Chainlink's recommended pattern
- This forwards 2,300 gas, which is sufficient for EOA (Externally Owned Account) recipients
- **Contract users**: If your contract has a `receive()` or `fallback()` function, ensure it uses minimal gas (< 2,300) or use an EOA intermediary for bridging

**Bridge Risk Warning:**
- Tokens are **burned on the source chain** before the CCIP message is sent
- If CCIP message delivery fails (network issues, service limits, etc.), tokens are **permanently lost**
- Users should understand CCIP service limits and potential failure modes before bridging
- See [Chainlink CCIP Service Limits](https://docs.chain.link/ccip/service-limits) for details

### Flash Loans

```solidity
// Use ERC-3156 Flash Mint
IERC3156FlashBorrower borrower = ...;
uint256 amount = ...;
bytes calldata data = ...;
flashLoan(borrower, address(this), amount, data);
```

### Admin Functions

```solidity
// Set admin address (for chain and CCIP management)
function setAdmin(address _admin) external;

// Manage allowed mining chains
function setAllowedChain(uint256 chainId, bool allowed) external;

// Manage CCIP destination chains
function setAllowedDestinationChain(uint64 chainSelector, bool allowed, string memory name) external;

// Configure CCIP parameters
function setCCIPExtraArgs(uint256 newGasLimit, bool newAllowOutOfOrderExecution) external;
```

## Key Functions

### Mining Functions
- `mint(uint256 nonce, bytes32)` - Mine tokens (EIP-918)
- `mintTo(uint256 nonce, address minter)` - Mine to specific address
- `getChallengeNumber()` - Get current PoW challenge
- `getMiningDifficulty()` - Get current difficulty
- `getMiningTarget()` - Get current mining target
- `getMiningReward()` - Get base reward amount (EIP-918 compliance - returns 23 ERIS base reward)
  - **Note**: Actual rewards use tiered system (11.5-529 ERIS). See Discordian Reward System section.
- `minedSupply()` - Get total tokens minted via PoW

### Cross-Chain Functions
- `sendCCIPCrossChainBridge(string, uint256)` - Bridge via CCIP
- `getCCIPCrossChainBridgeFee(string, uint256)` - Get bridge fee
- `crosschainMint(address, uint256)` - Superchain mint (internal)
- `crosschainBurn(address, uint256)` - Superchain burn (internal)

### Admin Functions
- `setAdmin(address)` - Set authorized admin address
- `setAllowedChain(uint256, bool)` - Enable/disable mining on chain
- `setAllowedDestinationChain(uint64, bool, string)` - Manage CCIP chains
- `setCCIPExtraArgs(uint256, bool)` - Configure CCIP parameters

## Technical Details

### Difficulty Adjustment Parameters
- **Adjustment Period**: 23 epochs (Discordian retarget)
- **Target Blocks**: 1,380 Ethereum blocks per period (23 × 60)
- **Adjustment Divisor**: 20,000 (gentle scaling)
- **Target Range**: 2^16 (hardest) to 2^234 (easiest)

### Mining Parameters
- **Base Reward**: 23 ERIS tokens
- **Reward Tiers**: 5 tiers with multipliers from 0.5× to 23×
- **Reward Range**: 11.5 ERIS (Discordant) to 529 ERIS (Enigma23)
- **Expected Value**: ~49.45 ERIS per successful mine
- **Mining Start**: Configurable timestamp

### Security Features
- **One reward per Ethereum block** - Prevents multiple rewards in same block
- **Challenge number rotation** - Updates after each mint to prevent pre-mining
- **Anti-gaming RNG** - Uses PoW digest instead of miner-controlled nonce
- **Multi-source entropy** - Combines unpredictable sources to prevent manipulation
- **Bounds checking** - All adjustments are bounded to prevent overflow/underflow
- **Overflow protection** - Built-in Solidity 0.8.28 protection
- **Authorized admin functions** - Chain and CCIP management restricted to admin
- **Immutable mining start timestamp** - Prevents pre-mining attacks by fixing launch time at deployment
- **Deterministic deployment enforcement** - CCIP security check ensures only legitimate contract messages are accepted

## Testing

```bash
# Run all tests
npx hardhat test

# Run Solidity tests only
npx hardhat test solidity

# Run TypeScript/Node.js tests only
npx hardhat test nodejs
```

## Network Configuration

The project supports deployment to multiple networks. See `hardhat.config.ts` for full network configuration including:
- Mainnet chains (Base, Ethereum, Arbitrum, Polygon, BNB, etc.)
- Testnet chains (Sepolia variants)
- Custom chain configurations

## Dependencies

### Production
- `@openzeppelin/contracts` - ERC-20, ERC-20Permit, ERC-20Burnable, ERC-20FlashMint
- `@chainlink/contracts-ccip` - Chainlink CCIP integration

### Development
- `hardhat` - Development framework
- `@nomicfoundation/hardhat-toolbox-viem` - Hardhat toolbox with viem
- `@nomicfoundation/hardhat-ignition` - Deployment system
- `viem` - Ethereum library
- `typescript` - TypeScript support

## License

MIT

## Disclaimer

This is a memecoin project. Use at your own risk. Always conduct your own research and due diligence before interacting with smart contracts.
