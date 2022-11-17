import hre, { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { PositionManager__factory } from "../../../typechain-types";
import log from "ololog";

const depositFee = 30; // 0.3%

async function main() {
  const PositionManager = (await ethers.getContractFactory(
    "PositionManager"
  )) as PositionManager__factory;

  const vault = "​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115";
  const router = "0x3d831BF3fDf54da1D34Ad3f329571dfE800c6142";
  const weth = "0x1b6A3d5B5DCdF7a37CFE35CeBC0C4bD28eA7e946";
  const orderbook = "0xF3Cc843E6138Eb62f09BB5C16733721055e7785b";

  const positionManager = await PositionManager.deploy(
    "​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115",
    "0x3d831BF3fDf54da1D34Ad3f329571dfE800c6142",
    "0x1b6A3d5B5DCdF7a37CFE35CeBC0C4bD28eA7e946",
    BigNumber.from("30"),
    "0xF3Cc843E6138Eb62f09BB5C16733721055e7785b"
  );

  log.green("PositionManager address: " + positionManager.address);

  // const timelock = "";
  // const orderbookKeeper = "";
  // const liquidator = "";
  // const partnerContracts = [];

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
