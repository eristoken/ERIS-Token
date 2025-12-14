import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { zeroAddress } from "viem";

export default buildModule("ERISSepolia", (m) => {
  // Pass address(0) to use automatic router selection based on chain ID
  const ERISSepolia = m.contract("ERISSepolia", [zeroAddress]);

  return { ERISSepolia };
});

