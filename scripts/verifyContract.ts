/**
 * Script to verify contracts by reading addresses from deployed_addresses.json
 */

import { readFileSync } from "fs";
import { execSync } from "child_process";
import { join } from "path";
import { zeroAddress } from "viem";

// Chain ID to deployment path mapping
const CHAIN_DEPLOYMENT_PATHS: Record<string, string> = {
  "421614": "ignition/deployments/chain-421614/deployed_addresses.json", // Arbitrum Sepolia
  "11155111": "ignition/deployments/chain-11155111/deployed_addresses.json", // Sepolia
  "84532": "ignition/deployments/chain-84532/deployed_addresses.json", // Base Sepolia
  "8453": "ignition/deployments/chain-8453/deployed_addresses.json", // Base
  "97": "ignition/deployments/chain-97/deployed_addresses.json", // BSC Testnet
};

// Network to chain ID mapping
const NETWORK_CHAIN_IDS: Record<string, string> = {
  "arbitrum-sepolia": "421614",
  "sepolia": "11155111",
  "base-sepolia": "84532",
  "base": "8453",
  "bscTestnet": "97",
};

// Contract name mappings (module name to contract key in JSON)
const CONTRACT_KEYS: Record<string, string> = {
  "ERISTest": "ERISTest#ERISTest",
  "ERISSepolia": "ERISSepolia#ERISSepolia",
  "ERIS": "ERIS#ERIS",
};

interface VerifyConfig {
  network: string;
  contractName: string;
  contractPath: string;
  constructorArgs?: string[];
}

function getDeploymentPath(network: string): string {
  const chainId = NETWORK_CHAIN_IDS[network];
  if (!chainId) {
    throw new Error(`Unknown network: ${network}. Supported networks: ${Object.keys(NETWORK_CHAIN_IDS).join(", ")}`);
  }

  const path = CHAIN_DEPLOYMENT_PATHS[chainId];
  if (!path) {
    throw new Error(`No deployment path configured for chain ID: ${chainId}`);
  }

  return path;
}

function getContractAddress(deploymentPath: string, contractKey: string): string {
  try {
    const fullPath = join(process.cwd(), deploymentPath);
    const fileContent = readFileSync(fullPath, "utf-8");
    const addresses = JSON.parse(fileContent);

    const address = addresses[contractKey];
    if (!address) {
      throw new Error(
        `Contract address not found for key "${contractKey}" in ${deploymentPath}.\n` +
        `Available keys: ${Object.keys(addresses).join(", ")}`
      );
    }

    return address;
  } catch (error) {
    if (error instanceof Error) {
      if (error.message.includes("ENOENT")) {
        throw new Error(`Deployment file not found: ${deploymentPath}`);
      }
      throw error;
    }
    throw new Error(`Failed to read deployment file: ${error}`);
  }
}

function verifyContract(config: VerifyConfig) {
  const { network, contractName, contractPath, constructorArgs = [] } = config;

  // Get the contract key for the JSON file
  const contractKey = CONTRACT_KEYS[contractName];
  if (!contractKey) {
    throw new Error(
      `Unknown contract name: ${contractName}. Supported: ${Object.keys(CONTRACT_KEYS).join(", ")}`
    );
  }

  // Get deployment path
  const deploymentPath = getDeploymentPath(network);
  console.log(`Reading deployment file: ${deploymentPath}`);

  // Get contract address
  const contractAddress = getContractAddress(deploymentPath, contractKey);
  console.log(`Contract address: ${contractAddress}`);

  // Build verify command
  const args = [contractAddress, ...constructorArgs];
  const verifyCommand = `npx hardhat verify --network ${network} --contract ${contractPath} ${args.join(" ")}`;

  console.log(`\nRunning verification command:`);
  console.log(verifyCommand);
  console.log("");

  try {
    execSync(verifyCommand, { stdio: "inherit" });
    console.log("\n✅ Contract verified successfully!");
  } catch (error) {
    console.error("\n❌ Verification failed");
    process.exit(1);
  }
}

// Main execution
const network = process.argv[2];
const contractName = process.argv[3];

if (!network || !contractName) {
  console.error("Usage: tsx scripts/verifyContract.ts <network> <contractName>");
  console.error("\nExample:");
  console.error("  tsx scripts/verifyContract.ts arbitrum-sepolia ERISTest");
  console.error("  tsx scripts/verifyContract.ts sepolia ERISSepolia");
  console.error("\nSupported networks:", Object.keys(NETWORK_CHAIN_IDS).join(", "));
  console.error("Supported contracts:", Object.keys(CONTRACT_KEYS).join(", "));
  process.exit(1);
}

// Contract path mappings
const CONTRACT_PATHS: Record<string, string> = {
  "ERISTest": "contracts/ERISTest.sol:ERISTest",
  "ERISSepolia": "contracts/ERISSepolia.sol:ERISSepolia",
  "ERIS": "contracts/ERIS.sol:ERIS",
};

const contractPath = CONTRACT_PATHS[contractName];
if (!contractPath) {
  console.error(`Unknown contract: ${contractName}`);
  process.exit(1);
}

// Constructor arguments - ERISTest and ERISSepolia use zeroAddress
const constructorArgs: string[] = [];
if (contractName === "ERISTest" || contractName === "ERISSepolia") {
  constructorArgs.push(zeroAddress);
}

verifyContract({
  network,
  contractName,
  contractPath,
  constructorArgs,
});

