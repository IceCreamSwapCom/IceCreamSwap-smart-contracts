import { ethers } from "hardhat";
import { tryVerify } from "./verify";
import prompt from "./nodePrompt";
import { Libraries } from "@nomicfoundation/hardhat-ethers/types";

export const deployOnly = async (
  contractName: string,
  constructorArguments: any[] = [],
  libraries: Libraries = {},
) => {
  const ContractFactory = await ethers.getContractFactory(contractName, { libraries: libraries });

  const deploymentTx = await ContractFactory.getDeployTransaction(...constructorArguments);
  const gasEstimate = await ethers.provider.estimateGas({
    from: "0x0000000000000000000000000000000000000000",
    data: deploymentTx.data,
  });
  const feeData = await ethers.provider.getFeeData();
  const deploymentCost =
    gasEstimate * (feeData.maxFeePerGas ? feeData.maxFeePerGas + feeData.maxPriorityFeePerGas! : feeData.gasPrice!);
  const balance = await ethers.provider.getBalance((await ethers.getSigners())[0].address);
  const minimumBalance = (deploymentCost * 150n) / 100n;
  if (minimumBalance > balance) {
    await prompt(
      `Deployer wallet balance to low for deployment. missing ${minimumBalance - balance} wei of native token. Please refill and hit enter`,
    );
  }

  const deployedContract = await ContractFactory.deploy(...constructorArguments);
  await deployedContract.waitForDeployment();
  console.log(`${contractName} deployed to ${deployedContract.target.toString()}`);

  return deployedContract;
};
