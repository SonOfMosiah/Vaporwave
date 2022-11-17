import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { expandDecimals, reportGasUsed } from "../../shared/utilities";
import { toChainlinkPrice } from "../../shared/chainlink";
import { initVault, getBnbConfig, getEthConfig, getBtcConfig } from "./helpers";

describe("Vault.swap", function () {
  let user0: any, user1: any, user2: any, user3: any;
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
    [user0, user1, user2, user3] = await ethers.getSigners();
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

    vlp = await deployContract("VLP", []);
    vlpManager = await deployContract("VlpManager", [
      vault.address,
      usdv.address,
      vlp.address,
      24 * 60 * 60,
    ]);
  });

  it("swap", async () => {
    await expect(
      vault.connect(user1).swap(bnb.address, btc.address, user2.address)
    ).to.be.revertedWith("Vault: _tokenIn not allowlisted");

    await vault.setIsSwapEnabled(false);

    await expect(
      vault.connect(user1).swap(bnb.address, btc.address, user2.address)
    ).to.be.revertedWith("Vault: swaps not enabled");

    await vault.setIsSwapEnabled(true);

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await expect(
      vault.connect(user1).swap(bnb.address, btc.address, user2.address)
    ).to.be.revertedWith("Vault: _tokenOut not allowlisted");

    await expect(
      vault.connect(user1).swap(bnb.address, bnb.address, user2.address)
    ).to.be.revertedWith("Vault: invalid tokens");

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await bnb.mint(user0.address, expandDecimals(200, 18));
    await btc.mint(user0.address, expandDecimals(1, 8));

    expect(await vlpManager.getAumInUsdv(false)).eq(0);

    await bnb.connect(user0).transfer(vault.address, expandDecimals(200, 18));
    await vault.connect(user0).buyUSDV(bnb.address, user0.address);

    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(59820, 18)); // 60,000 * 99.7%

    await btc.connect(user0).transfer(vault.address, expandDecimals(1, 8));
    await vault.connect(user0).buyUSDV(btc.address, user0.address);

    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(119640, 18)); // 59,820 + (60,000 * 99.7%)

    expect(await usdv.balanceOf(user0.address)).eq(
      expandDecimals(120000, 18).sub(expandDecimals(360, 18))
    ); // 120,000 * 0.3% => 360

    expect(await vault.feeReserves(bnb.address)).eq("600000000000000000"); // 200 * 0.3% => 0.6
    expect(await vault.usdvAmounts(bnb.address)).eq(
      expandDecimals(200 * 300, 18).sub(expandDecimals(180, 18))
    ); // 60,000 * 0.3% => 180
    expect(await vault.poolAmounts(bnb.address)).eq(
      expandDecimals(200, 18).sub("600000000000000000")
    );

    expect(await vault.feeReserves(btc.address)).eq("300000"); // 1 * 0.3% => 0.003
    expect(await vault.usdvAmounts(btc.address)).eq(
      expandDecimals(200 * 300, 18).sub(expandDecimals(180, 18))
    );
    expect(await vault.poolAmounts(btc.address)).eq(
      expandDecimals(1, 8).sub("300000")
    );

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500));

    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(139580, 18)); // 59,820 / 300 * 400 + 59820

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(90000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(100000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(80000));

    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(159520, 18)); // 59,820 / 300 * 400 + 59820 / 60000 * 80000

    await bnb.mint(user1.address, expandDecimals(100, 18));
    await bnb.connect(user1).transfer(vault.address, expandDecimals(100, 18));

    expect(await btc.balanceOf(user1.address)).eq(0);
    expect(await btc.balanceOf(user2.address)).eq(0);
    const tx = await vault
      .connect(user1)
      .swap(bnb.address, btc.address, user2.address);
    await reportGasUsed(tx, "swap gas used");

    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(167520, 18)); // 159520 + (100 * 400) - 32000

    expect(await btc.balanceOf(user1.address)).eq(0);
    expect(await btc.balanceOf(user2.address)).eq(
      expandDecimals(4, 7).sub("120000")
    ); // 0.8 - 0.0012

    expect(await vault.feeReserves(bnb.address)).eq("600000000000000000"); // 200 * 0.3% => 0.6
    expect(await vault.usdvAmounts(bnb.address)).eq(
      expandDecimals(100 * 400, 18)
        .add(expandDecimals(200 * 300, 18))
        .sub(expandDecimals(180, 18))
    );
    expect(await vault.poolAmounts(bnb.address)).eq(
      expandDecimals(100, 18)
        .add(expandDecimals(200, 18))
        .sub("600000000000000000")
    );

    expect(await vault.feeReserves(btc.address)).eq("420000"); // 1 * 0.3% => 0.003, 0.4 * 0.3% => 0.0012
    expect(await vault.usdvAmounts(btc.address)).eq(
      expandDecimals(200 * 300, 18)
        .sub(expandDecimals(180, 18))
        .sub(expandDecimals(100 * 400, 18))
    );
    expect(await vault.poolAmounts(btc.address)).eq(
      expandDecimals(1, 8).sub("300000").sub(expandDecimals(4, 7))
    ); // 59700000, 0.597 BTC, 0.597 * 100,000 => 59700

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(400));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(500));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(450));

    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await bnb.balanceOf(user3.address)).eq(0);
    await usdv
      .connect(user0)
      .transfer(vault.address, expandDecimals(50000, 18));
    await vault.sellUSDV(bnb.address, user3.address);
    expect(await bnb.balanceOf(user0.address)).eq(0);
    expect(await bnb.balanceOf(user3.address)).eq("99700000000000000000"); // 99.7, 50000 / 500 * 99.7%

    await usdv
      .connect(user0)
      .transfer(vault.address, expandDecimals(50000, 18));
    await vault.sellUSDV(btc.address, user3.address);

    await usdv
      .connect(user0)
      .transfer(vault.address, expandDecimals(10000, 18));
    await expect(vault.sellUSDV(btc.address, user3.address)).to.be.revertedWith(
      "Vault: poolAmount exceeded"
    );
  });

  it("caps max USDV amount", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600));
    await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3000));

    const bnbConfig = getBnbConfig(bnb, bnbPriceFeed);
    const ethConfig = getBnbConfig(eth, ethPriceFeed);

    bnbConfig[4] = expandDecimals(299000, 18);
    await vault.setTokenConfig(...bnbConfig);

    ethConfig[4] = expandDecimals(30000, 18);
    await vault.setTokenConfig(...ethConfig);

    await bnb.mint(user0.address, expandDecimals(499, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(499, 18));
    await vault.connect(user0).buyUSDV(bnb.address, user0.address);

    await eth.mint(user0.address, expandDecimals(10, 18));
    await eth.connect(user0).transfer(vault.address, expandDecimals(10, 18));
    await vault.connect(user0).buyUSDV(eth.address, user1.address);

    await bnb.mint(user0.address, expandDecimals(1, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(1, 18));

    await expect(
      vault.connect(user0).buyUSDV(bnb.address, user0.address)
    ).to.be.revertedWith("Vault: max USDV exceeded");

    bnbConfig[4] = expandDecimals(299100, 18);
    await vault.setTokenConfig(...bnbConfig);

    await vault.connect(user0).buyUSDV(bnb.address, user0.address);

    await bnb.mint(user0.address, expandDecimals(1, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(1, 18));
    await expect(
      vault.connect(user0).swap(bnb.address, eth.address, user1.address)
    ).to.be.revertedWith("Vault: max USDV exceeded");

    bnbConfig[4] = expandDecimals(299700, 18);
    await vault.setTokenConfig(...bnbConfig);
    await vault.connect(user0).swap(bnb.address, eth.address, user1.address);
  });

  it("does not cap max USDV debt", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3000));
    await vault.setTokenConfig(...getEthConfig(eth, ethPriceFeed));

    await bnb.mint(user0.address, expandDecimals(100, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(100, 18));
    await vault.connect(user0).buyUSDV(bnb.address, user0.address);

    await eth.mint(user0.address, expandDecimals(10, 18));

    expect(await eth.balanceOf(user0.address)).eq(expandDecimals(10, 18));
    expect(await bnb.balanceOf(user1.address)).eq(0);

    await eth.connect(user0).transfer(vault.address, expandDecimals(10, 18));
    await vault.connect(user0).swap(eth.address, bnb.address, user1.address);

    expect(await eth.balanceOf(user0.address)).eq(0);
    expect(await bnb.balanceOf(user1.address)).eq("49850000000000000000");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));

    await eth.mint(user0.address, expandDecimals(1, 18));
    await eth.connect(user0).transfer(vault.address, expandDecimals(1, 18));
    await vault.connect(user0).swap(eth.address, bnb.address, user1.address);
  });

  it("ensures poolAmount >= buffer", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(600));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await ethPriceFeed.setLatestAnswer(toChainlinkPrice(3000));
    await vault.setTokenConfig(...getEthConfig(eth, ethPriceFeed));

    await bnb.mint(user0.address, expandDecimals(100, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(100, 18));
    await vault.connect(user0).buyUSDV(bnb.address, user0.address);

    await vault.setBufferAmount(bnb.address, "94700000000000000000"); // 94.7

    expect(await vault.poolAmounts(bnb.address)).eq("99700000000000000000"); // 99.7
    expect(await vault.poolAmounts(eth.address)).eq(0);
    expect(await bnb.balanceOf(user1.address)).eq(0);
    expect(await eth.balanceOf(user1.address)).eq(0);

    await eth.mint(user0.address, expandDecimals(1, 18));
    await eth.connect(user0).transfer(vault.address, expandDecimals(1, 18));
    await vault.connect(user0).swap(eth.address, bnb.address, user1.address);

    expect(await vault.poolAmounts(bnb.address)).eq("94700000000000000000"); // 94.7
    expect(await vault.poolAmounts(eth.address)).eq(expandDecimals(1, 18));
    expect(await bnb.balanceOf(user1.address)).eq("4985000000000000000"); // 4.985
    expect(await eth.balanceOf(user1.address)).eq(0);

    await eth.mint(user0.address, expandDecimals(1, 18));
    await eth.connect(user0).transfer(vault.address, expandDecimals(1, 18));
    await expect(
      vault.connect(user0).swap(eth.address, bnb.address, user1.address)
    ).to.be.revertedWith("Vault: poolAmount < buffer");
  });
});
