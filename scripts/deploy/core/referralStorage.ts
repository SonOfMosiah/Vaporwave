import hre, { ethers } from "hardhat";
import { ReferralStorage__factory } from "../../../typechain-types";
import log from "ololog";

async function main() {
  const ReferralStorage = (await ethers.getContractFactory(
    "ReferralStorage"
  )) as ReferralStorage__factory;

  const referralStorage = await ReferralStorage.deploy();
  log.yellow("ReferralStorage address: ", referralStorage.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
