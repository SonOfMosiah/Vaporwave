import hre, { ethers } from "hardhat";
import { Router__factory } from "../../../typechain-types";
import log from "ololog";

async function main() {
  const vault = {
    address: "​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115",
  };
  const vaultAddress = "​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115";

  const Router = (await ethers.getContractFactory("Router")) as Router__factory;

  const weth = "0x1b6A3d5B5DCdF7a37CFE35CeBC0C4bD28eA7e946";

  const router = await Router.deploy(vaultAddress, weth);
  log.yellow("Router address: ", router.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
