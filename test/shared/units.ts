import { ethers } from "hardhat";

export function toUsd(value: any) {
  const normalizedValue = (value * Math.pow(10, 10)).toString();
  return ethers.BigNumber.from(normalizedValue).mul(
    ethers.BigNumber.from(10).pow(20)
  );
}

export function toNormalizedPrice(value: any) {
  const normalizedValue = (value * Math.pow(10, 10)).toString();
  return ethers.BigNumber.from(normalizedValue).mul(
    ethers.BigNumber.from(10).pow(20)
  );
}
