import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { expandDecimals } from "../../shared/utilities";
import { toChainlinkPrice } from "../../shared/chainlink";
import { initVault, getBnbConfig, getBtcConfig } from "./helpers";

describe("Vault.withdrawFees", function () {
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

  it("withdrawFees", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await bnb.mint(user0.address, expandDecimals(900, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(900, 18));

    expect(await usdv.balanceOf(wallet.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);

    await vault.connect(user0).buyUSDV(bnb.address, user1.address);

    expect(await usdv.balanceOf(wallet.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq("269190000000000000000000"); // 269,190 USDV, 810 fee
    expect(await vault.feeReserves(bnb.address)).eq("2700000000000000000"); // 2.7, 900 * 0.3%
    expect(await vault.usdvAmounts(bnb.address)).eq("269190000000000000000000"); // 269,190
    expect(await vault.poolAmounts(bnb.address)).eq("897300000000000000000"); // 897.3
    expect(await usdv.totalSupply()).eq("269190000000000000000000");

    await bnb.mint(user0.address, expandDecimals(200, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(200, 18));

    await btc.mint(user0.address, expandDecimals(2, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(2, 8));

    await vault.connect(user0).buyUSDV(btc.address, user1.address);
    expect(await vault.usdvAmounts(btc.address)).eq("119640000000000000000000"); // 119,640
    expect(await usdv.totalSupply()).eq("388830000000000000000000"); // 388,830

    await btc.mint(user0.address, expandDecimals(2, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(2, 8));

    await vault.connect(user0).buyUSDV(btc.address, user1.address);
    expect(await vault.usdvAmounts(btc.address)).eq("239280000000000000000000"); // 239,280
    expect(await usdv.totalSupply()).eq("508470000000000000000000"); // 508,470

    expect(await vault.usdvAmounts(bnb.address)).eq("269190000000000000000000"); // 269,190
    expect(await vault.poolAmounts(bnb.address)).eq("897300000000000000000"); // 897.3

    await vault.connect(user0).buyUSDV(bnb.address, user1.address);

    expect(await vault.usdvAmounts(bnb.address)).eq("329010000000000000000000"); // 329,010
    expect(await vault.poolAmounts(bnb.address)).eq("1096700000000000000000"); // 1096.7

    expect(await vault.feeReserves(bnb.address)).eq("3300000000000000000"); // 3.3 BNB
    expect(await vault.feeReserves(btc.address)).eq("1200000"); // 0.012 BTC

    await expect(
      vault.connect(user0).withdrawFees(bnb.address, user2.address)
    ).to.be.revertedWith("Vault: forbidden");

    expect(await bnb.balanceOf(user2.address)).eq(0);
    await vault.withdrawFees(bnb.address, user2.address);
    expect(await bnb.balanceOf(user2.address)).eq("3300000000000000000");

    expect(await btc.balanceOf(user2.address)).eq(0);
    await vault.withdrawFees(btc.address, user2.address);
    expect(await btc.balanceOf(user2.address)).eq("1200000");
  });

  it("withdrawFees using timelock", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await bnb.mint(user0.address, expandDecimals(900, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(900, 18));

    expect(await usdv.balanceOf(wallet.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);

    await vault.connect(user0).buyUSDV(bnb.address, user1.address);

    expect(await usdv.balanceOf(wallet.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq("269190000000000000000000"); // 269,190 USDV, 810 fee
    expect(await vault.feeReserves(bnb.address)).eq("2700000000000000000"); // 2.7, 900 * 0.3%
    expect(await vault.usdvAmounts(bnb.address)).eq("269190000000000000000000"); // 269,190
    expect(await vault.poolAmounts(bnb.address)).eq("897300000000000000000"); // 897.3
    expect(await usdv.totalSupply()).eq("269190000000000000000000");

    await bnb.mint(user0.address, expandDecimals(200, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(200, 18));

    await btc.mint(user0.address, expandDecimals(2, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(2, 8));

    await vault.connect(user0).buyUSDV(btc.address, user1.address);
    expect(await vault.usdvAmounts(btc.address)).eq("119640000000000000000000"); // 119,640
    expect(await usdv.totalSupply()).eq("388830000000000000000000"); // 388,830

    await btc.mint(user0.address, expandDecimals(2, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(2, 8));

    await vault.connect(user0).buyUSDV(btc.address, user1.address);
    expect(await vault.usdvAmounts(btc.address)).eq("239280000000000000000000"); // 239,280
    expect(await usdv.totalSupply()).eq("508470000000000000000000"); // 508,470

    expect(await vault.usdvAmounts(bnb.address)).eq("269190000000000000000000"); // 269,190
    expect(await vault.poolAmounts(bnb.address)).eq("897300000000000000000"); // 897.3

    await vault.connect(user0).buyUSDV(bnb.address, user1.address);

    expect(await vault.usdvAmounts(bnb.address)).eq("329010000000000000000000"); // 329,010
    expect(await vault.poolAmounts(bnb.address)).eq("1096700000000000000000"); // 1096.7

    expect(await vault.feeReserves(bnb.address)).eq("3300000000000000000"); // 3.3 BNB
    expect(await vault.feeReserves(btc.address)).eq("1200000"); // 0.012 BTC

    await expect(
      vault.connect(user0).withdrawFees(bnb.address, user2.address)
    ).to.be.revertedWith("Vault: forbidden");

    const timelock = await deployContract("Timelock", [
      wallet.address,
      5 * 24 * 60 * 60,
      user0.address,
      user1.address,
      user2.address,
      expandDecimals(1000, 18),
      10,
      100,
    ]);
    await vault.setGov(timelock.address);

    await expect(
      timelock
        .connect(user0)
        .withdrawFees(vault.address, bnb.address, user2.address)
    ).to.be.revertedWith("Timelock: forbidden");

    expect(await bnb.balanceOf(user2.address)).eq(0);
    await timelock.withdrawFees(vault.address, bnb.address, user2.address);
    expect(await bnb.balanceOf(user2.address)).eq("3300000000000000000");

    expect(await btc.balanceOf(user2.address)).eq(0);
    await timelock.withdrawFees(vault.address, btc.address, user2.address);
    expect(await btc.balanceOf(user2.address)).eq("1200000");
  });
});
