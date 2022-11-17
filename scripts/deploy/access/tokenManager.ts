import hre, { ethers } from "hardhat";
import { TokenManager__factory } from "../../../typechain-types";
import log from "ololog";

async function main() {
  const TokenManager = (await ethers.getContractFactory(
    "TokenManager"
  )) as TokenManager__factory;
  const tokenManager = await TokenManager.deploy("3");

  log.green("TokenManager address: " + tokenManager.address);

  // // TODO: add signers
  // const signers = [];

  // let init = await tokenManager.initialize(signers);
  // await init.wait();
  // log.yellow("init:", init.hash);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
