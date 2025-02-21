import { deployOnly, getChainConfig } from "@icecreamswap/common";
import { writeFileSync } from "fs";

async function main() {
  const { chainName } = await getChainConfig();

  const executor = await deployOnly("AggregatorExecutor", []);

  const contracts = {
    executor: executor.target,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
