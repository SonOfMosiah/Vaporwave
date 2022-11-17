import { ethers } from "hardhat";

export async function deployContract(name: string, args: any) {
  const contractFactory = await ethers.getContractFactory(name);
  return await contractFactory.deploy(...args);
}

export async function contractAt(name: string, address: string) {
  const contractFactory = await ethers.getContractFactory(name);
  return await contractFactory.attach(address);
}
