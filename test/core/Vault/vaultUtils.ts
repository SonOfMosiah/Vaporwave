import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { initVault } from "./helpers";

describe("VaultUtils", function () {
  let wallet: any, user0: any;
  let vault: any;
  let vaultUtils: any;
  let vaultPriceFeed: any;
  let usdv: any;
  let router: any;
  let bnb: any;

  before(async () => {
    [wallet, user0] = await ethers.getSigners();
  });

  beforeEach(async () => {
    bnb = await deployContract("Token", []);

    vault = await deployContract("Vault", []);
    usdv = await deployContract("USDV", [vault.address]);
    router = await deployContract("Router", [
      vault.address,
      usdv.address,
      bnb.address,
    ]);
    vaultPriceFeed = await deployContract("VaultPriceFeed", []);

    const _ = await initVault(vault, router, usdv, vaultPriceFeed);
    vaultUtils = _.vaultUtils;
  });
});
