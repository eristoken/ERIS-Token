import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { zeroAddress } from "viem";

export default buildModule("ERISTest", (m) => {
  // Pass address(0) to use automatic router selection based on chain ID
  const ERISTest = m.contract("ERISTest", [zeroAddress]);

  return { ERISTest };
});

