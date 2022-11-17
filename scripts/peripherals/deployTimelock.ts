import hre, { ethers } from "hardhat";
import { Vault__factory, Timelock__factory } from "../../typechain-types";
import log from "ololog";

const network = process.env.HARDHAT_NETWORK || "mainnet";

async function main() {
  const admin = "";
  const buffer = 24 * 60 * 60;
  const rewardManager = { address: ethers.constants.AddressZero };
  const maxTokenSupply = ethers.utils.parseEther("50000");

  const Vault = (await ethers.getContractFactory("Vault")) as Vault__factory;
  const vault = Vault.attach("​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115");

  const tokenManager = {
    address: "",
  };
  const mintReceiver = {
    address: "",
  };

  const positionRouter = {
    address: "",
  };
  const positionManager = {
    address: "",
  };

  const Timelock = (await ethers.getContractFactory(
    "Timelock"
  )) as Timelock__factory;
  const timelock = Timelock.deploy(
    admin,
    buffer,
    rewardManager.address,
    tokenManager.address,
    mintReceiver.address,
    maxTokenSupply,
    10, // marginFeeBasisPoints 0.1%
    100 // maxMarginFeeBasisPoints 1%);
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
