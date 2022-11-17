import hre, { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { PositionRouter__factory } from "../../../typechain-types";
import log from "ololog";

const depositFee = 30; // 0.3%
const minExecutionFee = "300000000000000";

async function main() {
  const PositionRouter = (await ethers.getContractFactory(
    "PositionRouter"
  )) as PositionRouter__factory;

  const vault = "​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115";
  const router = "0x3d831BF3fDf54da1D34Ad3f329571dfE800c6142";
  const weth = "0x1b6A3d5B5DCdF7a37CFE35CeBC0C4bD28eA7e946";
  const orderbook = "0xF3Cc843E6138Eb62f09BB5C16733721055e7785b";

  const positionRouter = await PositionRouter.deploy(
    "​​0xEF6d716A1D02994ce4C0A2Acc2fFB854B84C6115",
    "0x3d831BF3fDf54da1D34Ad3f329571dfE800c6142",
    "0x1b6A3d5B5DCdF7a37CFE35CeBC0C4bD28eA7e946",
    "30",
    "300000000000000"
  );

  log.green("PositionRouter address: " + positionRouter.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
