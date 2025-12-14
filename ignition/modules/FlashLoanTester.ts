import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("FlashLoanTester", (m) => {
  // Replace with the actual deployed ERC20FlashMint token address
  const flashLoanProviderAddress = "0x2824F37FFB0c4Fd4e63Bf8F4CBc49700C4d381C2";

  // Pass the constructor argument to the contract
  const FlashLoanTester = m.contract("FlashLoanTester", [flashLoanProviderAddress]);

  return { FlashLoanTester };
});
