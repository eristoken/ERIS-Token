import { network } from "hardhat";
import { parseUnits, formatUnits, encodeFunctionData, decodeEventLog } from "viem";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * Chain Name Mapping
 * Maps lowercase chain identifiers to contract chain names
 */
const CHAIN_NAME_MAP: Record<string, string> = {
  // Mainnets
  ethereum: "Ethereum",
  base: "Base",
  polygon: "Polygon",
  bnb: "BNB",
  arbitrum: "Arbitrum One",
  ink: "Ink",
  worldchain: "World Chain",
  soneium: "Soneium",
  unichain: "Unichain",
};

/**
 * CCIP Chain Selectors (kept for reference/compatibility)
 * These are Chainlink CCIP chain selectors, not EVM chain IDs
 */
const CCIP_CHAIN_SELECTORS: Record<string, bigint> = {
  // Mainnets
  ethereum: 5009297550715157269n,      // Ethereum Mainnet
  base: 15971525489660198786n,          // Base
  polygon: 4051577828743386545n,        // Polygon
  bnb: 11344663589394136015n,           // BNB Smart Chain
  arbitrum: 4949039107694359620n,       // Arbitrum One
  ink: 3461204551265785888n,            // Ink
  worldchain: 2049429975587534727n,     // World Chain
  soneium: 12505351618335765396n,       // Soneium
  unichain: 1923510103922296319n,       // Unichain
};

/**
 * Example: Bridge ERIS tokens cross-chain using Chainlink CCIP
 * 
 * This script demonstrates:
 * 1. Getting the bridge fee estimate
 * 2. Checking token balance and approval
 * 3. Executing the cross-chain bridge transaction
 * 4. Monitoring transaction status
 */
async function bridgeTokens() {
  try {
    const { viem } = await network.connect({
      network: "hardhat",
      chainType: "evm",
    });

    const publicClient = await viem.getPublicClient();
    const [walletClient] = await viem.getWalletClients();

    // Configuration - Set these in your .env file or modify here
    const ERIS_CONTRACT_ADDRESS = process.env.ERIS_CONTRACT_ADDRESS || process.env.ERIS_CONTRACT_ADDRESS || "";
    const DESTINATION_CHAIN = process.env.DESTINATION_CHAIN || "base"; // e.g., "base", "polygon", "arbitrum"
    const AMOUNT = process.env.BRIDGE_AMOUNT || "100"; // Amount in tokens (will be converted to wei)

    if (!ERIS_CONTRACT_ADDRESS) {
      throw new Error("ERIS_CONTRACT_ADDRESS (or ERIS_CONTRACT_ADDRESS) not set in .env");
    }

    const chainKey = DESTINATION_CHAIN.toLowerCase();
    const destinationChainName = CHAIN_NAME_MAP[chainKey];
    if (!destinationChainName) {
      throw new Error(
        `Unknown destination chain: ${DESTINATION_CHAIN}. Available chains: ${Object.keys(CHAIN_NAME_MAP).join(", ")}`
      );
    }

    const amountWei = parseUnits(AMOUNT, 18); // ERIS uses 18 decimals
    const senderAddress = walletClient.account.address;

    console.log("\n=== Cross-Chain Bridge Configuration ===");
    console.log(`Contract Address: ${ERIS_CONTRACT_ADDRESS}`);
    console.log(`Sender: ${senderAddress}`);
    console.log(`Destination Chain: ${destinationChainName}`);
    console.log(`Amount: ${AMOUNT} ERIS (${amountWei.toString()} wei)`);
    console.log(`Receiver: ${ERIS_CONTRACT_ADDRESS} (deterministic deployment)`);

    // Get current chain ID
    const currentChainId = await publicClient.getChainId();
    console.log(`Current Chain ID: ${currentChainId}`);

    // Step 1: Check token balance
    console.log("\n=== Step 1: Checking Token Balance ===");
    const balanceABI = [
      {
        inputs: [{ name: "account", type: "address" }],
        name: "balanceOf",
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
      },
    ] as const;

    const balance = await publicClient.readContract({
      address: ERIS_CONTRACT_ADDRESS as `0x${string}`,
      abi: balanceABI,
      functionName: "balanceOf",
      args: [senderAddress],
    });

    console.log(`Token Balance: ${formatUnits(balance, 18)} ERIS`);

    if (balance < amountWei) {
      throw new Error(
        `Insufficient balance. Need ${formatUnits(amountWei, 18)} ERIS, have ${formatUnits(balance, 18)} ERIS`
      );
    }

    // Step 2: Check if approval is needed (if using ERC20 transferFrom pattern)
    // Note: The bridge function burns tokens directly, so no approval needed
    // But we'll check allowance anyway for completeness
    console.log("\n=== Step 2: Checking Allowance ===");
    const allowanceABI = [
      {
        inputs: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
        ],
        name: "allowance",
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
      },
    ] as const;

    // Since sendCCIPCrossChainBridge burns directly, no approval needed
    console.log("No approval needed - bridge function burns tokens directly");

    // Step 3: Get bridge fee estimate
    console.log("\n=== Step 3: Getting Bridge Fee Estimate ===");
    const getBridgeFeeABI = [
      {
        inputs: [
          { name: "destinationChainName", type: "string" },
          { name: "amount", type: "uint256" },
        ],
        name: "getBridgeFee",
        outputs: [{ name: "fee", type: "uint256" }],
        stateMutability: "view",
        type: "function",
      },
    ] as const;

    const bridgeFee = await publicClient.readContract({
      address: ERIS_CONTRACT_ADDRESS as `0x${string}`,
      abi: getBridgeFeeABI,
      functionName: "getBridgeFee",
      args: [destinationChainName, amountWei],
    });

    console.log(`Bridge Fee: ${formatUnits(bridgeFee, 18)} ETH`);
    console.log(`Bridge Fee (wei): ${bridgeFee.toString()}`);

    // Step 4: Check native token balance for fees
    const nativeBalance = await publicClient.getBalance({
      address: senderAddress,
    });

    console.log(`Native Balance: ${formatUnits(nativeBalance, 18)} ETH`);

    // Add 10% buffer for gas and fee fluctuations
    const feeWithBuffer = (bridgeFee * 110n) / 100n;

    if (nativeBalance < feeWithBuffer) {
      throw new Error(
        `Insufficient native token for fees. Need at least ${formatUnits(feeWithBuffer, 18)} ETH, have ${formatUnits(nativeBalance, 18)} ETH`
      );
    }

    // Step 5: Prepare and send bridge transaction
    console.log("\n=== Step 4: Preparing Bridge Transaction ===");
    const bridgeABI = [
      {
        inputs: [
          { name: "destinationChainName", type: "string" },
          { name: "amount", type: "uint256" },
        ],
        name: "sendCCIPCrossChainBridge",
        outputs: [],
        stateMutability: "payable",
        type: "function",
      },
    ] as const;

    // Estimate gas
    console.log("Estimating gas...");
    const gasEstimate = await publicClient.estimateGas({
      account: senderAddress,
      to: ERIS_CONTRACT_ADDRESS as `0x${string}`,
      data: encodeFunctionData({
        abi: bridgeABI,
        functionName: "sendCCIPCrossChainBridge",
        args: [destinationChainName, amountWei],
      }),
      value: feeWithBuffer,
    });

    console.log(`Estimated Gas: ${gasEstimate.toString()}`);

    // Step 6: Send transaction
    console.log("\n=== Step 5: Sending Bridge Transaction ===");
    const hash = await walletClient.sendTransaction({
      to: ERIS_CONTRACT_ADDRESS as `0x${string}`,
      data: encodeFunctionData({
        abi: bridgeABI,
        functionName: "sendCCIPCrossChainBridge",
        args: [destinationChainName, amountWei],
      }),
      value: feeWithBuffer,
      gas: gasEstimate,
    });

    console.log(`Transaction Hash: ${hash}`);
    console.log("Waiting for confirmation...");

    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log(`\n✅ Transaction confirmed!`);
    console.log(`Block Number: ${receipt.blockNumber}`);
    console.log(`Gas Used: ${receipt.gasUsed.toString()}`);

    // Look for CrossChainSent event
    const crossChainSentEventABI = [
      {
        inputs: [
          { indexed: true, name: "messageId", type: "bytes32" },
          { indexed: true, name: "destinationChain", type: "uint64" },
          { indexed: false, name: "amount", type: "uint256" },
          { indexed: false, name: "owner", type: "address" },
        ],
        name: "CrossChainSent",
        type: "event",
      },
    ] as const;

    for (const log of receipt.logs) {
      try {
        const decoded = decodeEventLog({
          abi: crossChainSentEventABI,
          data: log.data,
          topics: log.topics,
        });

        if (decoded.eventName === "CrossChainSent") {
          console.log("\n📤 Cross-chain message sent successfully!");
          console.log(`Message ID: ${decoded.args.messageId}`);
          console.log(`Destination Chain: ${decoded.args.destinationChain}`);
          console.log(`Amount: ${formatUnits(decoded.args.amount, 18)} ERIS`);
          console.log(`Owner: ${decoded.args.owner}`);
          console.log("\nTokens will be minted on destination chain after CCIP processes the message.");
          console.log(`Monitor the transaction on CCIP explorer for message status.`);
          break;
        }
      } catch {
        // Not the event we're looking for, continue
      }
    }

    console.log("\n=== Bridge Transaction Complete ===");
    console.log(`Amount: ${AMOUNT} ERIS`);
    console.log(`From: Chain ${currentChainId}`);
    console.log(`To: ${destinationChainName}`);
    console.log(`Message will be processed by CCIP and tokens minted on destination chain.`);

  } catch (error) {
    console.error("\n❌ Error bridging tokens:", error);
    if (error instanceof Error) {
      console.error(`Error message: ${error.message}`);
    }
    throw error;
  }
}

/**
 * Example: Just get the bridge fee without bridging
 */
async function getBridgeFeeExample() {
  try {
    const { viem } = await network.connect({
      network: "hardhat",
      chainType: "evm",
    });

    const publicClient = await viem.getPublicClient();
    const [walletClient] = await viem.getWalletClients();

    const ERIS_CONTRACT_ADDRESS = process.env.ERIS_CONTRACT_ADDRESS || process.env.ERIS_CONTRACT_ADDRESS || "";
    const DESTINATION_CHAIN = process.env.DESTINATION_CHAIN || "base";
    const AMOUNT = process.env.BRIDGE_AMOUNT || "100";

    if (!ERIS_CONTRACT_ADDRESS) {
      throw new Error("ERIS_CONTRACT_ADDRESS (or ERIS_CONTRACT_ADDRESS) not set in .env");
    }

    const chainKey = DESTINATION_CHAIN.toLowerCase();
    const destinationChainName = CHAIN_NAME_MAP[chainKey];
    if (!destinationChainName) {
      throw new Error(`Unknown destination chain: ${DESTINATION_CHAIN}`);
    }

    const amountWei = parseUnits(AMOUNT, 18);
    const senderAddress = walletClient.account.address;

    const getBridgeFeeABI = [
      {
        inputs: [
          { name: "destinationChainName", type: "string" },
          { name: "amount", type: "uint256" },
        ],
        name: "getBridgeFee",
        outputs: [{ name: "fee", type: "uint256" }],
        stateMutability: "view",
        type: "function",
      },
    ] as const;

    const fee = await publicClient.readContract({
      address: ERIS_CONTRACT_ADDRESS as `0x${string}`,
      abi: getBridgeFeeABI,
      functionName: "getBridgeFee",
      args: [destinationChainName, amountWei],
    });

    console.log("\n=== Bridge Fee Estimate ===");
    console.log(`Amount: ${AMOUNT} ERIS`);
    console.log(`Destination: ${destinationChainName}`);
    console.log(`Fee: ${formatUnits(fee, 18)} ETH`);
    console.log(`Fee (wei): ${fee.toString()}`);

    return fee;
  } catch (error) {
    console.error("Error getting bridge fee:", error);
    throw error;
  }
}

// Run example
if (require.main === module) {
  // Uncomment the function you want to run:
  // getBridgeFeeExample();
  // bridgeTokens();

  console.log("Cross-chain bridge example script loaded.");
  console.log("\nAvailable functions:");
  console.log("  - getBridgeFeeExample() - Get fee estimate without bridging");
  console.log("  - bridgeTokens() - Complete bridge transaction");
  console.log("\nEnvironment variables needed:");
  console.log("  - ERIS_CONTRACT_ADDRESS: The ERIS contract address (or ERIS_CONTRACT_ADDRESS for backward compatibility)");
  console.log("  - DESTINATION_CHAIN: Destination chain (base, polygon, arbitrum, etc.)");
  console.log("  - BRIDGE_AMOUNT: Amount to bridge in tokens (default: 100)");
  console.log("  Note: Receiver is always the contract address due to deterministic deployment");
}

export { bridgeTokens, getBridgeFeeExample, CCIP_CHAIN_SELECTORS, CHAIN_NAME_MAP };

