import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { toChainlinkPrice } from "../../shared/chainlink";
import { initVault, getBnbConfig, validateVaultBalance } from "./helpers";

describe("Vault.settings", function () {
  let wallet: any, user0: any, user1: any, user2: any, user3: any;
  let vault: any;
  let vaultPriceFeed: any;
  let usdv: any;
  let router: any;
  let bnb: any;
  let bnbPriceFeed: any;
  let btc: any;
  let btcPriceFeed: any;
  let dai: any;
  let daiPriceFeed: any;
  let eth: any;
  let ethPriceFeed: any;
  let distributor0: any;
  let yieldTracker0: any;

  before(async () => {
    [wallet, user0, user1, user2, user3] = await ethers.getSigners();
  });

  beforeEach(async () => {
    bnb = await deployContract("Token", []);
    bnbPriceFeed = await deployContract("PriceFeed", []);

    btc = await deployContract("Token", []);
    btcPriceFeed = await deployContract("PriceFeed", []);

    dai = await deployContract("Token", []);
    daiPriceFeed = await deployContract("PriceFeed", []);

    vault = await deployContract("Vault", []);
    usdv = await deployContract("USDV", [vault.address]);
    router = await deployContract("Router", [
      vault.address,
      usdv.address,
      bnb.address,
    ]);
    vaultPriceFeed = await deployContract("VaultPriceFeed", []);

    await initVault(vault, router, usdv, vaultPriceFeed);

    distributor0 = await deployContract("TimeDistributor", []);
    yieldTracker0 = await deployContract("YieldTracker", [usdv.address]);

    await yieldTracker0.setDistributor(distributor0.address);
    await distributor0.setDistribution(
      [yieldTracker0.address],
      [1000],
      [bnb.address]
    );

    await bnb.mint(distributor0.address, 5000);
    await usdv.setYieldTrackers([yieldTracker0.address]);

    await vaultPriceFeed.setTokenConfig(
      bnb.address,
      bnbPriceFeed.address,
      8,
      false
    );
    await vaultPriceFeed.setTokenConfig(
      btc.address,
      btcPriceFeed.address,
      8,
      false
    );
    await vaultPriceFeed.setTokenConfig(
      dai.address,
      daiPriceFeed.address,
      8,
      false
    );
  });

  it("directPoolDeposit", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));

    await expect(
      vault.connect(user0).directPoolDeposit(bnb.address)
    ).to.be.revertedWith("Vault: _token not allowlisted");

    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await expect(
      vault.connect(user0).directPoolDeposit(bnb.address)
    ).to.be.revertedWith("Vault: invalid tokenAmount");

    await bnb.mint(user0.address, 1000);
    await bnb.connect(user0).transfer(vault.address, 1000);

    expect(await vault.poolAmounts(bnb.address)).eq(0);
    await vault.connect(user0).directPoolDeposit(bnb.address);
    expect(await vault.poolAmounts(bnb.address)).eq(1000);

    await validateVaultBalance(expect, vault, bnb);
  });
});
