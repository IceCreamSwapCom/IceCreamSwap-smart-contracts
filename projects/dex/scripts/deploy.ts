import { deployAndVerify, dexConfig, getChainConfig, transactSafe } from "@icecreamswap/common";
import { writeFileSync } from "fs";
import { ethers } from "hardhat";

async function main() {
  const { chainConfig, chainName } = await getChainConfig();

  const factory = await deployAndVerify("IceCreamSwapV2Factory", [(await ethers.getSigners())[0].address, 100]);
  await transactSafe(factory.setFeeTo, [dexConfig.feeCollector]);
  await transactSafe(factory.setFeeToSetter, [dexConfig.dexAdmin]);

  const router = await deployAndVerify("IceCreamSwapV2Router", [factory.target, chainConfig.weth]);

  const initCodeHash = await factory.INIT_CODE_HASH();

  const contracts = {
    factory: factory.target.toString(),
    router: router.target.toString(),
    initCodeHash,
    deploymentTs: Math.floor(Date.now() / 1000),
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
