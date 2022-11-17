import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { expandDecimals, reportGasUsed } from "../../shared/utilities";
import { toChainlinkPrice } from "../../shared/chainlink";
import { toUsd } from "../../shared/units";
import { initVault, getBnbConfig, getBtcConfig, getDaiConfig } from "./helpers";

describe("Vault.sellUSDV", function () {
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

  let vlpManager: any;
  let vlp: any;

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

    vlp = await deployContract("VLP", []);
    vlpManager = await deployContract("VlpManager", [
      vault.address,
      usdv.address,
      vlp.address,
      24 * 60 * 60,
    ]);
  });

  it("sellUSDV", async () => {
    await expect(
      vault.connect(user0).sellUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: _token not allowlisted");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await bnb.mint(user0.address, 100);

    expect(await vlpManager.getAumInUsdv(true)).eq(0);
    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);
    expect(await bnb.balanceOf(user0.address)).eq(100);
    await bnb.connect(user0).transfer(vault.address, 100);
    await vault.connect(user0).buyUSDV(bnb.address, user0.address);
    expect(await usdv.balanceOf(user0.address)).eq(29700);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(1);
    expect(await vault.usdvAmounts(bnb.address)).eq(29700);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1);
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await vlpManager.getAumInUsdv(true)).eq(29700);

    await expect(
      vault.connect(user0).sellUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: invalid usdvAmount");

    await usdv.connect(user0).transfer(vault.address, 15000);

    await expect(
      vault.connect(user0).sellUSDV(btc.address, user1.address)
    ).to.be.revertedWith("Vault: invalid redemptionAmount");

    await vault.setInManagerMode(true);
    await expect(
      vault.connect(user0).sellUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: forbidden");

    await vault.setManager(user0.address, true);

    const tx = await vault
      .connect(user0)
      .sellUSDV(bnb.address, user1.address, { gasPrice: "10000000000" });
    await reportGasUsed(tx, "sellUSDV gas used");
    expect(await usdv.balanceOf(user0.address)).eq(29700 - 15000);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(2);
    expect(await vault.usdvAmounts(bnb.address)).eq(29700 - 15000);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1 - 50);
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await bnb.balanceOf(user1.address)).eq(50 - 1); // (15000 / 300) => 50
    expect(await vlpManager.getAumInUsdv(true)).eq(29700 - 15000);
  });

  it("sellUSDV after a price increase", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await bnb.mint(user0.address, 100);

    expect(await vlpManager.getAumInUsdv(true)).eq(0);
    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);
    expect(await bnb.balanceOf(user0.address)).eq(100);
    await bnb.connect(user0).transfer(vault.address, 100);
    await vault.connect(user0).buyUSDV(bnb.address, user0.address);

    expect(await usdv.balanceOf(user0.address)).eq(29700);
    expect(await usdv.balanceOf(user1.address)).eq(0);

    expect(await vault.feeReserves(bnb.address)).eq(1);
    expect(await vault.usdvAmounts(bnb.address)).eq(29700);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1);
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await vlpManager.getAumInUsdv(true)).eq(29700);

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500));

    expect(await vlpManager.getAumInUsdv(false)).eq(39600);

    await usdv.connect(user0).transfer(vault.address, 15000);
    await vault.connect(user0).sellUSDV(bnb.address, user1.address);

    expect(await usdv.balanceOf(user0.address)).eq(29700 - 15000);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(2);
    expect(await vault.usdvAmounts(bnb.address)).eq(29700 - 15000);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1 - 25);
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await bnb.balanceOf(user1.address)).eq(25 - 1); // (15000 / 600) => 25
    expect(await vlpManager.getAumInUsdv(false)).eq(29600);
  });

  it("sellUSDV redeem based on price", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await btc.mint(user0.address, expandDecimals(2, 8));

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(btc.address)).eq(0);
    expect(await vault.usdvAmounts(btc.address)).eq(0);
    expect(await vault.poolAmounts(btc.address)).eq(0);
    expect(await btc.balanceOf(user0.address)).eq(expandDecimals(2, 8));

    expect(await vlpManager.getAumInUsdv(true)).eq(0);
    await btc.connect(user0).transfer(vault.address, expandDecimals(2, 8));
    await vault.connect(user0).buyUSDV(btc.address, user0.address);
    expect(await vlpManager.getAumInUsdv(true)).eq("119640000000000000000000"); // 119,640

    expect(await usdv.balanceOf(user0.address)).eq("119640000000000000000000"); // 119,640
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(btc.address)).eq("600000"); // 0.006 BTC, 2 * 0.03%
    expect(await vault.usdvAmounts(btc.address)).eq("119640000000000000000000"); // 119,640
    expect(await vault.poolAmounts(btc.address)).eq("199400000"); // 1.994 BTC
    expect(await btc.balanceOf(user0.address)).eq(0);
    expect(await btc.balanceOf(user1.address)).eq(0);

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(82000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(80000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(83000));

    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(159520, 18)); // 199400000 / (10 ** 8) * 80,000
    await usdv
      .connect(user0)
      .transfer(vault.address, expandDecimals(10000, 18));
    await vault.connect(user0).sellUSDV(btc.address, user1.address);

    expect(await btc.balanceOf(user1.address)).eq("12012047"); // 0.12012047 BTC, 0.12012047 * 83000 => 9969.999
    expect(await vault.feeReserves(btc.address)).eq("636145"); // 0.00636145
    expect(await vault.poolAmounts(btc.address)).eq("187351808"); // 199400000-(636145-600000)-12012047 => 187351808
    expect(await vlpManager.getAumInUsdv(false)).eq("149881446400000000000000"); // 149881.4464, 187351808 / (10 ** 8) * 80,000
  });

  it("sellUSDV for stableTokens", async () => {
    await vault.setFees(
      50, // _taxBasisPoints
      10, // _stableTaxBasisPoints
      4, // _mintBurnFeeBasisPoints
      30, // _swapFeeBasisPoints
      4, // _stableSwapFeeBasisPoints
      10, // _marginFeeBasisPoints
      toUsd(5), // _liquidationFeeUsd
      0, // _minProfitTime
      false // _hasDynamicFees
    );

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1));
    await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed));

    await dai.mint(user0.address, expandDecimals(10000, 18));

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(dai.address)).eq(0);
    expect(await vault.usdvAmounts(dai.address)).eq(0);
    expect(await vault.poolAmounts(dai.address)).eq(0);
    expect(await dai.balanceOf(user0.address)).eq(expandDecimals(10000, 18));
    expect(await vlpManager.getAumInUsdv(true)).eq(0);

    await dai.connect(user0).transfer(vault.address, expandDecimals(10000, 18));
    await vault.connect(user0).buyUSDV(dai.address, user0.address);

    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(9996, 18));
    expect(await usdv.balanceOf(user0.address)).eq(expandDecimals(9996, 18));
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(dai.address)).eq(expandDecimals(4, 18));
    expect(await vault.usdvAmounts(dai.address)).eq(expandDecimals(9996, 18));
    expect(await vault.poolAmounts(dai.address)).eq(expandDecimals(9996, 18));
    expect(await dai.balanceOf(user0.address)).eq(0);
    expect(await dai.balanceOf(user1.address)).eq(0);

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(5000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await btc.mint(user0.address, expandDecimals(1, 8));

    expect(await dai.balanceOf(user2.address)).eq(0);

    await btc.connect(user0).transfer(vault.address, expandDecimals(1, 8));
    await vault.connect(user0).swap(btc.address, dai.address, user2.address);

    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(9996, 18));

    expect(await vault.feeReserves(dai.address)).eq(expandDecimals(19, 18));
    expect(await vault.usdvAmounts(dai.address)).eq(expandDecimals(4996, 18));
    expect(await vault.poolAmounts(dai.address)).eq(expandDecimals(4996, 18));

    expect(await vault.feeReserves(btc.address)).eq(0);
    expect(await vault.usdvAmounts(btc.address)).eq(expandDecimals(5000, 18));
    expect(await vault.poolAmounts(btc.address)).eq(expandDecimals(1, 8));

    expect(await dai.balanceOf(user2.address)).eq(expandDecimals(4985, 18));

    await usdv.connect(user0).approve(router.address, expandDecimals(5000, 18));
    await expect(
      router
        .connect(user0)
        .swap(
          [usdv.address, dai.address],
          expandDecimals(5000, 18),
          0,
          user3.address
        )
    ).to.be.revertedWith("Vault: poolAmount exceeded");

    expect(await dai.balanceOf(user3.address)).eq(0);
    await router
      .connect(user0)
      .swap(
        [usdv.address, dai.address],
        expandDecimals(4000, 18),
        0,
        user3.address
      );
    expect(await dai.balanceOf(user3.address)).eq("3998400000000000000000"); // 3998.4

    expect(await vault.feeReserves(dai.address)).eq("20600000000000000000"); // 20.6
    expect(await vault.usdvAmounts(dai.address)).eq(expandDecimals(996, 18));
    expect(await vault.poolAmounts(dai.address)).eq(expandDecimals(996, 18));

    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(5996, 18));
  });
});
