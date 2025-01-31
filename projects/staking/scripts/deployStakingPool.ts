import { bridgeConfig, deployAndVerify, dexConfig, getChainConfig, transactSafe } from "@icecreamswap/common";
import { writeFileSync, existsSync, readFileSync } from "fs";
import { ethers } from "hardhat";
import prompt from "@icecreamswap/common/dist/nodePrompt";
import { toBigInt } from "ethers";

async function main() {
  const { chainConfig, chainName } = await getChainConfig();

  let contracts;
  let ChefFactoryInstance = null;
  if (!existsSync(`./deployments/${chainName}.json`)) {
    console.log(`No deployments found for ${chainName}. Start deploying SmartChefFactory`);
    ChefFactoryInstance = await deployAndVerify("SmartChefFactory", []);

    contracts = {
      factory: ChefFactoryInstance.target.toString(),
      deploymentTs: Math.floor(Date.now() / 1000),
      pools: [],
    };
    writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
  } else {
    contracts = JSON.parse(readFileSync(`./deployments/${chainName}.json`, { encoding: "utf8", flag: "r" }));
    console.log(`Using existing SmartChefFactory at ${contracts.factory}`);
    ChefFactoryInstance = await ethers.getContractAt("SmartChefFactory", contracts.factory);
  }

  
  // staked token address
  var staking_token_address = ethers.getAddress(await prompt(`Please enter the staked token address: `));

  // reward token address
  var reward_token_address = ethers.getAddress(await prompt(`Please enter the reward token address: `));

  // start block, if empty current block
  var start_block = parseInt(await prompt(`Please enter the start block. If empty = current block: `));
  if (isNaN(start_block) || start_block == 0) {
    start_block = await ethers.provider.getBlockNumber() + 10;
  }

  // end block
  var end_block = parseInt(await prompt(`Please enter the end block: `));
  if (isNaN(end_block) || end_block <= start_block) {
    throw "end block cant be smaller than start block";
  }

  // total reward per block (in rewardToken)
  var total_rewards = parseFloat(
    await prompt(`Please enter the amount of rewards you'd like to distribute. (in rewardToken): `),
  );

  // get reward token decimals
  const erc20Abi = ["function decimals() view returns (uint8)"];
  const signer = (await ethers.getSigners())[0];
  const tokenContract = new ethers.Contract(reward_token_address, erc20Abi, signer);
  const decimals = await tokenContract.decimals();
  // calculate reward per block (in rewardToken)
  const total_rewards_wei = ethers.parseUnits(total_rewards.toString(), decimals);
  var rewards_per_block_wei = total_rewards_wei / BigInt(end_block - start_block);

  // pool limit per user in stakedToken (if any, else 0)
  var pool_limit_per_user = parseInt(await prompt(`pool limit per user in stakedToken (if any, else 0): `));
  if (isNaN(pool_limit_per_user)) {
    pool_limit_per_user = 0;
  }
  // block numbers available for user limit (after start block)
  var block_number_limit_per_user = parseInt(await prompt(`pool limit per user in stakedToken (if any, else 0): `));
  if (isNaN(block_number_limit_per_user)) {
    block_number_limit_per_user = 0;
  }

  // deploy pool
  const receipt = await transactSafe(ChefFactoryInstance.deployPool, [
    staking_token_address,
    reward_token_address,
    rewards_per_block_wei,
    BigInt(start_block),
    BigInt(end_block),
    ethers.parseUnits(pool_limit_per_user.toString(), decimals),
    ethers.parseUnits(block_number_limit_per_user.toString(), decimals),
    dexConfig.dexAdmin,
  ]);
  //const receipt = await ethers.provider.getTransactionReceipt("0x64d3c1d2ceb75df5c8aff29c929822848990441b006a3f2e281ccd544c4895c0")
  console.log("Transaction sent. Waiting for confirmation...");


  // Extract the SmartChef contract address from event logs
  if (receipt.status != 1){
    throw 'Transaction failed';
  }

  for (let i = 1; i < receipt.logs.length; i++) {
    if (ChefFactoryInstance.interface.parseLog(receipt.logs[i])["name"] == "NewSmartChefContract") {
      let addressHex = receipt.logs[i]["topics"][1];
      if (addressHex.startsWith('0x000000000000000000000000')) {
        addressHex = '0x' + addressHex.slice(26); // Get the last 40 characters (the actual address)
      }
      const decodedAddress = ethers.getAddress(addressHex);

      contracts.pools.push({
        pool: decodedAddress,
        staking_token: staking_token_address,
        reward_token_address: reward_token_address,
        tokenPerBlock: ethers.formatUnits(rewards_per_block_wei, decimals)
      });

      writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));

    }
  }


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
