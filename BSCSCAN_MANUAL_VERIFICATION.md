# BSCscan Manual Verification Guide for ERIS Token

This guide provides step-by-step instructions for manually verifying the ERIS contract on BSCscan.

## Contract Information

- **Contract Address:** `0xe9032e6d3f5eA3f405dAD92bC388ae0E3a538E1A`
- **Network:** BNB Smart Chain (BSC) Mainnet (Chain ID: 56)
- **Compiler Version:** 0.8.28
- **License:** MIT
- **Optimization:** Enabled (200 runs)
- **EVM Version:** Cancun

## Prerequisites

1. Access to BSCscan: https://bscscan.com
2. The `standard-json-input.json` file from this repository
3. Your contract deployment transaction hash (for reference)

## Quick Reference: Constructor Arguments

**For BSCscan verification, use this EXACT value (WITHOUT 0x prefix):**
```
0000000000000000000000000000000000000000000000000000000000000000
```

**Copy-paste ready (no spaces, no 0x):**
```
0000000000000000000000000000000000000000000000000000000000000000
```

This is the ABI-encoded zero address (`address(0)`) used in your deployment.

## Step-by-Step Verification Process

### Step 1: Navigate to Contract Page

1. Go to [BSCscan](https://bscscan.com)
2. Search for your contract address: `0xe9032e6d3f5eA3f405dAD92bC388ae0E3a538E1A`
3. Click on the **Contract** tab
4. Click on **Verify and Publish**

### Step 2: Select Verification Method

1. Choose **Via Standard JSON Input** (recommended for complex contracts with dependencies)
   - This method uses the `standard-json-input.json` file which contains all flattened source code

### Step 3: Fill in Contract Details

Fill in the following information:

#### Compiler Information
- **Compiler Type:** `Solidity (Standard JSON Input)`
- **Compiler Version:** `v0.8.28+commit.0e0c0c0c` (or select the exact 0.8.28 version)
- **License:** `MIT`

#### Contract Information
- **Contract Name:** `contracts/ERIS.sol:ERIS`
  - Note: The contract name should match the path in your source file
- **Constructor Arguments (ABI-encoded):**
  
  **Try this format first (WITHOUT 0x prefix):**
  ```
  0000000000000000000000000000000000000000000000000000000000000000
  ```
  
  **If that doesn't work, try WITH 0x prefix:**
  ```
  0x0000000000000000000000000000000000000000000000000000000000000000
  ```
  
  **Important Notes:**
  - This is the ABI-encoded value for `address(0)` (zero address)
  - The constructor uses this to automatically select the BSC CCIP router: `0x34B03Cb9086d7D758AC55af71584F81A598759FE`
  - The encoded value is exactly 64 hex characters (32 bytes) representing the zero address
  - BSCscan may accept either format, but typically expects it WITHOUT the "0x" prefix

#### Standard JSON Input
1. Open the `standard-json-input.json` file from this repository
2. Copy the **entire contents** of the file
3. Paste it into the **Standard JSON Input** field on BSCscan

**Important:** The standard-json-input.json file contains:
- All flattened source code (including all dependencies)
- Compiler settings (optimizer, EVM version, etc.)
- Output selection settings

**Important Notes:**
- If you see a parser error mentioning "dotenv" or "[dotenv@", the file has been updated to remove that message
- If you see "Identifier already declared" errors for `IERC165`, the file has been fixed to remove duplicate interface declarations
- If you see "Identifier not found" for `IERC165CCIP`, the file has been updated to use `IERC165` instead
- Make sure you're using the latest version of `standard-json-input.json` from the repository

### Step 4: Additional Settings

The following settings are already included in `standard-json-input.json`, but verify they match:

- **Optimization:** Enabled
- **Runs:** 200
- **EVM Version:** Cancun

### Step 5: Submit for Verification

1. Complete any CAPTCHA verification if prompted
2. Click **Verify and Publish**
3. Wait for BSCscan to process the verification (usually takes 30-60 seconds)

### Step 6: Verification Success

If successful, you should see:
- ✅ **Contract Verified** message
- The contract source code will be visible on the contract page
- You can now interact with the contract using the verified ABI

## Alternative: Using Direct Router Address

If you prefer to use the direct BSC CCIP router address instead of `address(0)`, use this constructor argument:

**Without 0x prefix (recommended for BSCscan):**
```
00000000000000000000000034B03Cb9086d7D758AC55af71584F81A598759FE
```

**With 0x prefix (if needed):**
```
0x00000000000000000000000034B03Cb9086d7D758AC55af71584F81A598759FE
```

**Note:** This is functionally equivalent since the constructor automatically selects the router based on chain ID when `address(0)` is provided. However, **use the zero address encoding above** to match your actual deployment.

## Troubleshooting

### Common Issues and Solutions

#### 1. "Bytecode does not match"
- **Cause:** Constructor arguments are incorrect
- **Solution:** Double-check the ABI-encoded constructor arguments above
- **Verify:** Use a tool like [ABI Encoder](https://abi.hashex.org/) to verify the encoding

#### 2. "Compiler version mismatch"
- **Cause:** Wrong Solidity compiler version selected
- **Solution:** Ensure you select **exactly** version `0.8.28`
- **Check:** The version is specified in `standard-json-input.json` and `hardhat.config.ts`

#### 3. "Contract name does not match"
- **Cause:** Incorrect contract name or path
- **Solution:** Use `contracts/ERIS.sol:ERIS` as the contract name
- **Format:** `path/to/file.sol:ContractName`

#### 4. "Optimization settings mismatch"
- **Cause:** Optimizer settings don't match deployment
- **Solution:** Ensure optimization is enabled with 200 runs (already in standard-json-input.json)

#### 5. "Unable to verify"
- **Cause:** Standard JSON input file is corrupted or incomplete
- **Solution:** 
  - Re-download `standard-json-input.json` from the repository
  - Ensure the entire file content is copied (it's a large file)
  - Check that the JSON is valid (no syntax errors)

#### 6. "Invalid constructor arguments provided. Please verify that they are in ABI-encoded format"
- **Cause:** Incorrect ABI encoding format or wrong prefix
- **Solutions to try:**
  1. **Remove the "0x" prefix** (most common fix):
     ```
     0000000000000000000000000000000000000000000000000000000000000000
     ```
  2. **Add the "0x" prefix** if you tried without it:
     ```
     0x0000000000000000000000000000000000000000000000000000000000000000
     ```
  3. **Verify no extra spaces or characters:**
     - The string should be exactly 64 hex characters (without 0x) or 66 characters (with 0x)
     - No spaces, newlines, or special characters
  4. **Verify the encoding manually:**
     - The constructor takes: `constructor(address router)`
     - The value passed is: `0x0000000000000000000000000000000000000000` (zero address)
     - ABI-encoded as: `0000000000000000000000000000000000000000000000000000000000000000`
  5. **Use an online ABI encoder to verify:**
     - Visit: https://abi.hashex.org/
     - Select "Encode" tab
     - Enter type: `address`
     - Enter value: `0x0000000000000000000000000000000000000000`
     - Copy the result (without 0x prefix for BSCscan)

## Verification via Hardhat (Alternative Method)

If manual verification fails, you can also use Hardhat's verification plugin:

```bash
npx hardhat verify --network bsc 0xe9032e6d3f5eA3f405dAD92bC388ae0E3a538E1A 0x0000000000000000000000000000000000000000
```

**Note:** This requires:
- BSCscan API key in your `.env` file
- Correct network configuration in `hardhat.config.ts`

## Post-Verification

After successful verification:

1. **Contract Source Code** will be visible on BSCscan
2. **ABI** will be available for contract interaction
3. **Read/Write Contract** functions will be accessible
4. **Contract Events** will be properly indexed

## Verifying Constructor Arguments Encoding

If you're unsure about the encoding, you can verify it using these methods:

### Method 1: Online ABI Encoder
1. Visit: https://abi.hashex.org/
2. Click on the **"Encode"** tab
3. Enter the following:
   - **Type:** `address`
   - **Value:** `0x0000000000000000000000000000000000000000`
4. Click **"Encode"**
5. Copy the result (remove the "0x" prefix if present)
6. The result should be: `0000000000000000000000000000000000000000000000000000000000000000`

### Method 2: Using Node.js (viem)
```bash
node -e "const { encodeAbiParameters, parseAbiParameters } = require('viem'); console.log(encodeAbiParameters(parseAbiParameters('address'), ['0x0000000000000000000000000000000000000000']).slice(2));"
```

Expected output: `0000000000000000000000000000000000000000000000000000000000000000`

### Method 3: Check Your Deployment Transaction
1. Go to your contract's deployment transaction on BSCscan
2. Click on the transaction hash
3. Scroll down to "Input Data"
4. The constructor arguments are the last 64 characters (32 bytes) of the input data
5. Compare this with the encoding above

## Common Error Fix

**Error:** "Invalid constructor arguments provided. Please verify that they are in ABI-encoded format"

**Most Common Solution:** Remove the "0x" prefix from the constructor arguments field on BSCscan.

Use this exact value (copy-paste):
```
0000000000000000000000000000000000000000000000000000000000000000
```

## Additional Resources

- [BSCscan Verification Guide](https://docs.bscscan.com/getting-started/verifying-a-smart-contract)
- [Solidity Compiler Versions](https://github.com/ethereum/solidity/releases)
- [ABI Encoding Tools](https://abi.hashex.org/)
- [HashEx ABI Encoder](https://abi.hashex.org/) - Online tool to encode/decode ABI parameters

## Contract Details Summary

| Parameter | Value |
|-----------|-------|
| Contract Address | `0xe9032e6d3f5eA3f405dAD92bC388ae0E3a538E1A` |
| Network | BNB Smart Chain (BSC) Mainnet |
| Solidity Version | 0.8.28 |
| License | MIT |
| Optimization | Enabled (200 runs) |
| EVM Version | Cancun |
| Constructor Arg (with 0x) | `0x0000000000000000000000000000000000000000000000000000000000000000` |
| Constructor Arg (without 0x) | `0000000000000000000000000000000000000000000000000000000000000000` |
| CCIP Router (BSC) | `0x34B03Cb9086d7D758AC55af71584F81A598759FE` |

---

**Last Updated:** Based on deployment at `0xe9032e6d3f5eA3f405dAD92bC388ae0E3a538E1A`

