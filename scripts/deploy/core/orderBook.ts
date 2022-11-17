import hre, { ethers } from "hardhat";
import { OrderBook__factory } from "../../typechain-types";
import log from "ololog";

const network = process.env.HARDHAT_NETWORK || "mainnet";
const tokens = require("./tokens")[network];

async function main() {
  const { nativeToken } = tokens;

  const OrderBook = (await ethers.getContractFactory(
    "OrderBook"
  )) as OrderBook__factory;
  const orderBook = await OrderBook.deploy();

  log.green("orderBook address: " + orderBook.address);

  // const router = ""
  // const vault = ""
  // const weth = ""
  // const minExecutionFee = ""
  // const minPurchaseTokenAmountUsd = ""

  // let init = await orderBook.initialize(router, vault, weth, minExecutionFee, minPurchaseTokenAmountUsd);
  // await init.wait();
  // log.yellow("init:", init.hash);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
