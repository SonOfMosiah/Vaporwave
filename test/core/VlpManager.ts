import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../shared/fixtures";
import { time, mine } from "@nomicfoundation/hardhat-network-helpers";
import { expandDecimals, reportGasUsed, gasUsed } from "../shared/utilities";
import { toChainlinkPrice } from "../shared/chainlink";
import { toUsd, toNormalizedPrice } from "../shared/units";
import {
  initVault,
  getBnbConfig,
  getEthConfig,
  getBtcConfig,
  getDaiConfig,
  validateVaultBalance,
} from "./Vault/helpers";

describe("VlpManager", function () {
  let wallet: any,
    rewardRouter: any,
    user0: any,
    user1: any,
    user2: any,
    user3: any;
  let vault: any;
  let vlpManager: any;
  let vlp: any;
  let usdv: any;
  let router: any;
  let vaultPriceFeed: any;
  let bnb: any;
  let bnbPriceFeed: any;
  let btc: any;
  let btcPriceFeed: any;
  let eth;
  let ethPriceFeed;
  let dai: any;
  let daiPriceFeed: any;
  let busd: any;
  let busdPriceFeed: any;
  let distributor0: any;
  let yieldTracker0: any;
  let reader: any;

  before(async () => {
    [wallet, user0, user1, user2, user3, rewardRouter] =
      await ethers.getSigners();
  });

  beforeEach(async () => {
    bnb = await deployContract("Token", []);
    bnbPriceFeed = await deployContract("PriceFeed", []);

    btc = await deployContract("Token", []);
    btcPriceFeed = await deployContract("PriceFeed", []);

    eth = await deployContract("Token", []);
    ethPriceFeed = await deployContract("PriceFeed", []);

    dai = await deployContract("Token", []);
    daiPriceFeed = await deployContract("PriceFeed", []);

    busd = await deployContract("Token", []);
    busdPriceFeed = await deployContract("PriceFeed", []);

    vault = await deployContract("Vault", []);
    usdv = await deployContract("USDV", [vault.address]);
    router = await deployContract("Router", [
      vault.address,
      usdv.address,
      bnb.address,
    ]);
    vaultPriceFeed = await deployContract("VaultPriceFeed", []);
    vlp = await deployContract("VLP", []);

    await initVault(vault, router, usdv, vaultPriceFeed);
    vlpManager = await deployContract("VlpManager", [
      vault.address,
      usdv.address,
      vlp.address,
      24 * 60 * 60,
    ]);

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

    reader = await deployContract("Reader", []);

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
      eth.address,
      ethPriceFeed.address,
      8,
      false
    );
    await vaultPriceFeed.setTokenConfig(
      dai.address,
      daiPriceFeed.address,
      8,
      false
    );

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1));
    await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await vlp.setInPrivateTransferMode(true);
    await vlp.setMinter(vlpManager.address, true);

    await vault.setInManagerMode(true);
  });

  it("inits", async () => {
    expect(await vlpManager.gov()).eq(wallet.address);
    expect(await vlpManager.vault()).eq(vault.address);
    expect(await vlpManager.usdv()).eq(usdv.address);
    expect(await vlpManager.glp()).eq(vlp.address);
    expect(await vlpManager.cooldownDuration()).eq(24 * 60 * 60);
  });

  it("setGov", async () => {
    await expect(
      vlpManager.connect(user0).setGov(user1.address)
    ).to.be.revertedWith("Governable: forbidden");

    expect(await vlpManager.gov()).eq(wallet.address);

    await vlpManager.setGov(user0.address);
    expect(await vlpManager.gov()).eq(user0.address);

    await vlpManager.connect(user0).setGov(user1.address);
    expect(await vlpManager.gov()).eq(user1.address);
  });

  it("setHandler", async () => {
    await expect(
      vlpManager.connect(user0).setHandler(user1.address, true)
    ).to.be.revertedWith("Governable: forbidden");

    expect(await vlpManager.gov()).eq(wallet.address);
    await vlpManager.setGov(user0.address);
    expect(await vlpManager.gov()).eq(user0.address);

    expect(await vlpManager.isHandler(user1.address)).eq(false);
    await vlpManager.connect(user0).setHandler(user1.address, true);
    expect(await vlpManager.isHandler(user1.address)).eq(true);
  });

  it("setCooldownDuration", async () => {
    await expect(
      vlpManager.connect(user0).setCooldownDuration(1000)
    ).to.be.revertedWith("Governable: forbidden");

    await vlpManager.setGov(user0.address);

    await expect(
      vlpManager.connect(user0).setCooldownDuration(48 * 60 * 60 + 1)
    ).to.be.revertedWith("GlpManager: invalid _cooldownDuration");

    expect(await vlpManager.cooldownDuration()).eq(24 * 60 * 60);
    await vlpManager.connect(user0).setCooldownDuration(48 * 60 * 60);
    expect(await vlpManager.cooldownDuration()).eq(48 * 60 * 60);
  });

  it("setAumAdjustment", async () => {
    await expect(
      vlpManager.connect(user0).setAumAdjustment(29, 17)
    ).to.be.revertedWith("Governable: forbidden");

    await vlpManager.setGov(user0.address);

    expect(await vlpManager.aumAddition()).eq(0);
    expect(await vlpManager.aumDeduction()).eq(0);
    expect(await vlpManager.getAum(true)).eq(0);
    await vlpManager.connect(user0).setAumAdjustment(29, 17);
    expect(await vlpManager.aumAddition()).eq(29);
    expect(await vlpManager.aumDeduction()).eq(17);
    expect(await vlpManager.getAum(true)).eq(12);
  });

  it("addLiquidity, removeLiquidity", async () => {
    await dai.mint(user0.address, expandDecimals(100, 18));
    await dai
      .connect(user0)
      .approve(vlpManager.address, expandDecimals(100, 18));

    await expect(
      vlpManager
        .connect(user0)
        .addLiquidity(
          dai.address,
          expandDecimals(100, 18),
          expandDecimals(101, 18),
          expandDecimals(101, 18)
        )
    ).to.be.revertedWith("Vault: forbidden");

    await vault.setManager(vlpManager.address, true);

    await expect(
      vlpManager
        .connect(user0)
        .addLiquidity(
          dai.address,
          expandDecimals(100, 18),
          expandDecimals(101, 18),
          expandDecimals(101, 18)
        )
    ).to.be.revertedWith("GlpManager: insufficient USDV output");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400));

    expect(await dai.balanceOf(user0.address)).eq(expandDecimals(100, 18));
    expect(await dai.balanceOf(vault.address)).eq(0);
    expect(await usdv.balanceOf(vlpManager.address)).eq(0);
    expect(await vlp.balanceOf(user0.address)).eq(0);
    expect(await vlpManager.lastAddedAt(user0.address)).eq(0);
    expect(await vlpManager.getAumInUsdv(true)).eq(0);

    const tx0 = await vlpManager
      .connect(user0)
      .addLiquidity(
        dai.address,
        expandDecimals(100, 18),
        expandDecimals(99, 18),
        expandDecimals(99, 18)
      );
    await reportGasUsed(tx0, "addLiquidity gas used");

    let blockTime = await time.latest();

    expect(await dai.balanceOf(user0.address)).eq(0);
    expect(await dai.balanceOf(vault.address)).eq(expandDecimals(100, 18));
    expect(await usdv.balanceOf(vlpManager.address)).eq("99700000000000000000"); // 99.7
    expect(await vlp.balanceOf(user0.address)).eq("99700000000000000000");
    expect(await vlp.totalSupply()).eq("99700000000000000000");
    expect(await vlpManager.lastAddedAt(user0.address)).eq(blockTime);
    expect(await vlpManager.getAumInUsdv(true)).eq("99700000000000000000");
    expect(await vlpManager.getAumInUsdv(false)).eq("99700000000000000000");

    await bnb.mint(user1.address, expandDecimals(1, 18));
    await bnb.connect(user1).approve(vlpManager.address, expandDecimals(1, 18));

    await vlpManager
      .connect(user1)
      .addLiquidity(
        bnb.address,
        expandDecimals(1, 18),
        expandDecimals(299, 18),
        expandDecimals(299, 18)
      );
    blockTime = await time.latest();

    expect(await usdv.balanceOf(vlpManager.address)).eq(
      "398800000000000000000"
    ); // 398.8
    expect(await vlp.balanceOf(user0.address)).eq("99700000000000000000"); // 99.7
    expect(await vlp.balanceOf(user1.address)).eq("299100000000000000000"); // 299.1
    expect(await vlp.totalSupply()).eq("398800000000000000000");
    expect(await vlpManager.lastAddedAt(user1.address)).eq(blockTime);
    expect(await vlpManager.getAumInUsdv(true)).eq("498500000000000000000");
    expect(await vlpManager.getAumInUsdv(false)).eq("398800000000000000000");

    await expect(
      vlp.connect(user1).transfer(user2.address, expandDecimals(1, 18))
    ).to.be.revertedWith("BaseToken: msg.sender not allowlisted");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500));

    expect(await vlpManager.getAumInUsdv(true)).eq("598200000000000000000"); // 598.2
    expect(await vlpManager.getAumInUsdv(false)).eq("498500000000000000000"); // 498.5

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));

    await btc.mint(user2.address, "1000000"); // 0.01 BTC, $500
    await btc.connect(user2).approve(vlpManager.address, expandDecimals(1, 18));

    await expect(
      vlpManager
        .connect(user2)
        .addLiquidity(
          btc.address,
          "1000000",
          expandDecimals(599, 18),
          expandDecimals(399, 18)
        )
    ).to.be.revertedWith("GlpManager: insufficient USDV output");

    await expect(
      vlpManager
        .connect(user2)
        .addLiquidity(
          btc.address,
          "1000000",
          expandDecimals(598, 18),
          expandDecimals(399, 18)
        )
    ).to.be.revertedWith("GlpManager: insufficientvlpoutput");

    await vlpManager
      .connect(user2)
      .addLiquidity(
        btc.address,
        "1000000",
        expandDecimals(598, 18),
        expandDecimals(398, 18)
      );

    blockTime = await time.latest();

    expect(await usdv.balanceOf(vlpManager.address)).eq(
      "997000000000000000000"
    ); // 997
    expect(await vlp.balanceOf(user0.address)).eq("99700000000000000000"); // 99.7
    expect(await vlp.balanceOf(user1.address)).eq("299100000000000000000"); // 299.1
    expect(await vlp.balanceOf(user2.address)).eq("398800000000000000000"); // 398.8
    expect(await vlp.totalSupply()).eq("797600000000000000000"); // 797.6
    expect(await vlpManager.lastAddedAt(user2.address)).eq(blockTime);
    expect(await vlpManager.getAumInUsdv(true)).eq("1196400000000000000000"); // 1196.4
    expect(await vlpManager.getAumInUsdv(false)).eq("1096700000000000000000"); // 1096.7

    await expect(
      vlpManager
        .connect(user0)
        .removeLiquidity(
          dai.address,
          "99700000000000000000",
          expandDecimals(123, 18),
          user0.address
        )
    ).to.be.revertedWith("GlpManager: cooldown duration not yet passed");

    await time.increase(24 * 60 * 60 + 1);
    await mine();

    await expect(
      vlpManager
        .connect(user0)
        .removeLiquidity(
          dai.address,
          expandDecimals(73, 18),
          expandDecimals(100, 18),
          user0.address
        )
    ).to.be.revertedWith("Vault: poolAmount exceeded");

    expect(await dai.balanceOf(user0.address)).eq(0);
    expect(await vlp.balanceOf(user0.address)).eq("99700000000000000000"); // 99.7

    await vlpManager
      .connect(user0)
      .removeLiquidity(
        dai.address,
        expandDecimals(72, 18),
        expandDecimals(98, 18),
        user0.address
      );

    expect(await dai.balanceOf(user0.address)).eq("98703000000000000000"); // 98.703, 72 * 1096.7 / 797.6 => 99
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await vlp.balanceOf(user0.address)).eq("27700000000000000000"); // 27.7

    await vlpManager.connect(user0).removeLiquidity(
      bnb.address,
      "27700000000000000000", // 27.7, 27.7 * 1096.7 / 797.6 => 38.0875
      "75900000000000000", // 0.0759 BNB => 37.95 USD
      user0.address
    );

    expect(await dai.balanceOf(user0.address)).eq("98703000000000000000");
    expect(await bnb.balanceOf(user0.address)).eq("75946475000000000"); // 0.075946475
    expect(await vlp.balanceOf(user0.address)).eq(0);

    expect(await vlp.totalSupply()).eq("697900000000000000000"); // 697.9
    expect(await vlpManager.getAumInUsdv(true)).eq("1059312500000000000000"); // 1059.3125
    expect(await vlpManager.getAumInUsdv(false)).eq("967230000000000000000"); // 967.23

    expect(await bnb.balanceOf(user1.address)).eq(0);
    expect(await vlp.balanceOf(user1.address)).eq("299100000000000000000");

    await vlpManager.connect(user1).removeLiquidity(
      bnb.address,
      "299100000000000000000", // 299.1, 299.1 * 967.23 / 697.9 => 414.527142857
      "826500000000000000", // 0.8265 BNB => 413.25
      user1.address
    );

    expect(await bnb.balanceOf(user1.address)).eq("826567122857142856"); // 0.826567122857142856
    expect(await vlp.balanceOf(user1.address)).eq(0);

    expect(await vlp.totalSupply()).eq("398800000000000000000"); // 398.8
    expect(await vlpManager.getAumInUsdv(true)).eq("644785357142857143000"); // 644.785357142857143
    expect(await vlpManager.getAumInUsdv(false)).eq("635608285714285714400"); // 635.6082857142857144

    expect(await btc.balanceOf(user2.address)).eq(0);
    expect(await vlp.balanceOf(user2.address)).eq("398800000000000000000"); // 398.8

    expect(await vault.poolAmounts(dai.address)).eq("700000000000000000"); // 0.7
    expect(await vault.poolAmounts(bnb.address)).eq("91770714285714286"); // 0.091770714285714286
    expect(await vault.poolAmounts(btc.address)).eq("997000"); // 0.00997

    await expect(
      vlpManager.connect(user2).removeLiquidity(
        btc.address,
        expandDecimals(375, 18),
        "990000", // 0.0099
        user2.address
      )
    ).to.be.revertedWith("USDV: forbidden");

    await usdv.addVault(vlpManager.address);

    const tx1 = await vlpManager.connect(user2).removeLiquidity(
      btc.address,
      expandDecimals(375, 18),
      "990000", // 0.0099
      user2.address
    );
    await reportGasUsed(tx1, "removeLiquidity gas used");

    expect(await btc.balanceOf(user2.address)).eq("993137");
    expect(await vlp.balanceOf(user2.address)).eq("23800000000000000000"); // 23.8
  });

  it("addLiquidityForAccount, removeLiquidityForAccount", async () => {
    await vault.setManager(vlpManager.address, true);
    await vlpManager.setInPrivateMode(true);
    await vlpManager.setHandler(rewardRouter.address, true);

    await dai.mint(user3.address, expandDecimals(100, 18));
    await dai
      .connect(user3)
      .approve(vlpManager.address, expandDecimals(100, 18));

    await expect(
      vlpManager
        .connect(user0)
        .addLiquidityForAccount(
          user3.address,
          user0.address,
          dai.address,
          expandDecimals(100, 18),
          expandDecimals(101, 18),
          expandDecimals(101, 18)
        )
    ).to.be.revertedWith("GlpManager: forbidden");

    await expect(
      vlpManager
        .connect(rewardRouter)
        .addLiquidityForAccount(
          user3.address,
          user0.address,
          dai.address,
          expandDecimals(100, 18),
          expandDecimals(101, 18),
          expandDecimals(101, 18)
        )
    ).to.be.revertedWith("GlpManager: insufficient USDV output");

    expect(await dai.balanceOf(user3.address)).eq(expandDecimals(100, 18));
    expect(await dai.balanceOf(user0.address)).eq(0);
    expect(await dai.balanceOf(vault.address)).eq(0);
    expect(await usdv.balanceOf(vlpManager.address)).eq(0);
    expect(await vlp.balanceOf(user0.address)).eq(0);
    expect(await vlpManager.lastAddedAt(user0.address)).eq(0);
    expect(await vlpManager.getAumInUsdv(true)).eq(0);

    await vlpManager
      .connect(rewardRouter)
      .addLiquidityForAccount(
        user3.address,
        user0.address,
        dai.address,
        expandDecimals(100, 18),
        expandDecimals(99, 18),
        expandDecimals(99, 18)
      );

    let blockTime = await time.latest();

    expect(await dai.balanceOf(user3.address)).eq(0);
    expect(await dai.balanceOf(user0.address)).eq(0);
    expect(await dai.balanceOf(vault.address)).eq(expandDecimals(100, 18));
    expect(await usdv.balanceOf(vlpManager.address)).eq("99700000000000000000"); // 99.7
    expect(await vlp.balanceOf(user0.address)).eq("99700000000000000000");
    expect(await vlp.totalSupply()).eq("99700000000000000000");
    expect(await vlpManager.lastAddedAt(user0.address)).eq(blockTime);
    expect(await vlpManager.getAumInUsdv(true)).eq("99700000000000000000");

    await bnb.mint(user1.address, expandDecimals(1, 18));
    await bnb.connect(user1).approve(vlpManager.address, expandDecimals(1, 18));

    await time.increase(24 * 60 * 60 + 1);
    await mine();

    await vlpManager
      .connect(rewardRouter)
      .addLiquidityForAccount(
        user1.address,
        user1.address,
        bnb.address,
        expandDecimals(1, 18),
        expandDecimals(299, 18),
        expandDecimals(299, 18)
      );
    blockTime = await time.latest();

    expect(await usdv.balanceOf(vlpManager.address)).eq(
      "398800000000000000000"
    ); // 398.8
    expect(await vlp.balanceOf(user0.address)).eq("99700000000000000000");
    expect(await vlp.balanceOf(user1.address)).eq("299100000000000000000");
    expect(await vlp.totalSupply()).eq("398800000000000000000");
    expect(await vlpManager.lastAddedAt(user1.address)).eq(blockTime);
    expect(await vlpManager.getAumInUsdv(true)).eq("398800000000000000000");

    await expect(
      vlpManager
        .connect(user1)
        .removeLiquidityForAccount(
          user1.address,
          bnb.address,
          "99700000000000000000",
          expandDecimals(290, 18),
          user1.address
        )
    ).to.be.revertedWith("GlpManager: forbidden");

    await expect(
      vlpManager
        .connect(rewardRouter)
        .removeLiquidityForAccount(
          user1.address,
          bnb.address,
          "99700000000000000000",
          expandDecimals(290, 18),
          user1.address
        )
    ).to.be.revertedWith("GlpManager: cooldown duration not yet passed");

    await vlpManager.connect(rewardRouter).removeLiquidityForAccount(
      user0.address,
      dai.address,
      "79760000000000000000", // 79.76
      "79000000000000000000", // 79
      user0.address
    );

    expect(await dai.balanceOf(user0.address)).eq("79520720000000000000");
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await vlp.balanceOf(user0.address)).eq("19940000000000000000"); // 19.94
  });
});
