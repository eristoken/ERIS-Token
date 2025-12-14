import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { zeroAddress } from "viem";

export default buildModule("ERIS", (m) => {
  // Pass address(0) to use automatic router selection based on chain ID
  const ERIS = m.contract("ERIS", [zeroAddress]);

  return { ERIS };
});

