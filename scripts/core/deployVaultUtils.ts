import hre, { ethers } from "hardhat";
import {
  Vault__factory,
  VaultUtils__factory,
  Timelock__factory,
} from "../../typechain-types";
import log from "ololog";

const network = process.env.HARDHAT_NETWORK || "mainnet";
const tokens = require("./tokens")[network];

async function main() {
  const Vault = (await ethers.getContractFactory("Vault")) as Vault__factory;
  const vault = Vault.attach("​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115");

  const Timelock = (await ethers.getContractFactory(
    "Timelock"
  )) as Timelock__factory;
  const timelock = Timelock.attach(await vault.owner());

  const vlpManager = {
    address: = "";
  }

  const VaultUtils = (await ethers.getContractFactory(
    "VaultUtils"
  )) as VaultUtils__factory;
  const vaultUtils = await VaultUtils.deploy(vault.address, vlpManager.address);

  let setVaultUtils = await timelock.setVaultUtils(
    vault.address,
    vaultUtils.address
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
