import hre, { ethers } from "hardhat";
import {
  OrderBookReader__factory,
} from "../../typechain-types";
import log from "ololog";

async function main() {
  const OrderBookReader = (await ethers.getContractFactory ("OrderBookReader")) as OrderBookReader__factory;
  const orderBookReader = await OrderBookReader.deploy();
  log.yellow("OrderBookReader address: ", orderBookReader.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
