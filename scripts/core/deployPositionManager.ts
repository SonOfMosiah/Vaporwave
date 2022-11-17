import hre, { ethers } from "hardhat";
import { PositionManager__factory } from "../../typechain-types";
import log from "ololog";

const network = process.env.HARDHAT_NETWORK || "mainnet";
const tokens = require("./tokens")[network];

const depositFee = 30; // 0.3%

async function main() {
  const PositionManager = (await ethers.getContractFactory(
    "PositionManager"
  )) as PositionManager__factory;

  const vault = "";
  const router = "";
  const weth = "";
  const orderbook = "0xF3Cc843E6138Eb62f09BB5C16733721055e7785b";

  const positionManager = await PositionManager.deploy(
    vault,
    router,
    weth,
    depositFee,
    orderbook
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
