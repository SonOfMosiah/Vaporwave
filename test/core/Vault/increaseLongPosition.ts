import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { time, mine } from "@nomicfoundation/hardhat-network-helpers";
import { expandDecimals, reportGasUsed } from "../../shared/utilities";
import { toChainlinkPrice } from "../../shared/chainlink";
import { toUsd, toNormalizedPrice } from "../../shared/units";
import {
  initVault,
  getBnbConfig,
  getEthConfig,
  getBtcConfig,
  getDaiConfig,
  validateVaultBalance,
} from "./helpers";

describe("Vault.increaseLongPosition", function () {
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

    const initVaultResult = await initVault(
      vault,
      router,
      usdv,
      vaultPriceFeed
    );

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

  it("increasePosition long validations", async () => {
    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1));
    await vault.setMaxGasPrice("20000000000"); // 20 gwei
    await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed));
    await expect(
      vault
        .connect(user1)
        .increasePosition(user0.address, btc.address, btc.address, 0, true)
    ).to.be.revertedWith("Vault: invalid msg.sender");
    await expect(
      vault
        .connect(user1)
        .increasePosition(user0.address, btc.address, btc.address, 0, true, {
          gasPrice: "21000000000",
        })
    ).to.be.revertedWith("Vault: maxGasPrice exceeded");
    await vault.setMaxGasPrice(0);
    await vault.setIsLeverageEnabled(false);
    await expect(
      vault
        .connect(user1)
        .increasePosition(user0.address, btc.address, btc.address, 0, true, {
          gasPrice: "21000000000",
        })
    ).to.be.revertedWith("Vault: leverage not enabled");
    await vault.setIsLeverageEnabled(true);
    await vault.connect(user0).addRouter(user1.address);
    await expect(
      vault
        .connect(user1)
        .increasePosition(user0.address, btc.address, bnb.address, 0, true)
    ).to.be.revertedWith("Vault: mismatched tokens");
    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          bnb.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: mismatched tokens");
    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          dai.address,
          dai.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: _collateralToken must not be a stableToken");
    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: _collateralToken not allowlisted");

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(50000));

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: insufficient collateral for fees");
    await expect(
      vault
        .connect(user0)
        .increasePosition(user0.address, btc.address, btc.address, 0, true)
    ).to.be.revertedWith("Vault: invalid position.size");

    await btc.mint(user0.address, expandDecimals(1, 8));
    await btc.connect(user0).transfer(vault.address, 2500 - 1);

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: insufficient collateral for fees");

    await btc.connect(user0).transfer(vault.address, 1);

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: losses exceed collateral");

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: fees exceed collateral");

    await btc.connect(user0).transfer(vault.address, 10000);

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(1000),
          true
        )
    ).to.be.revertedWith("Vault: liquidation fees exceed collateral");

    await btc.connect(user0).transfer(vault.address, 10000);

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(500),
          true
        )
    ).to.be.revertedWith("Vault: maxLeverage exceeded");

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(8),
          true
        )
    ).to.be.revertedWith("Vault: _size must be more than _collateral");

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(47),
          true
        )
    ).to.be.revertedWith("Vault: reserve exceeds pool");
  });

  it("increasePosition long", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(50000));

    await btc.mint(user0.address, expandDecimals(1, 8));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(41000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(40000));

    await btc.connect(user0).transfer(vault.address, 117500 - 1); // 0.001174 BTC => 47

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(118),
          true
        )
    ).to.be.revertedWith("Vault: reserve exceeds pool");

    expect(await vault.feeReserves(btc.address)).eq(0);
    expect(await vault.usdvAmounts(btc.address)).eq(0);
    expect(await vault.poolAmounts(btc.address)).eq(0);

    expect(await vlpManager.getAumInUsdv(true)).eq(0);
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(0);
    await vault.buyUSDV(btc.address, user1.address);
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(
      toUsd("46.8584")
    );
    expect(await vlpManager.getAumInUsdv(true)).eq("48029860000000000000"); // 48.02986
    expect(await vlpManager.getAumInUsdv(false)).eq("46858400000000000000"); // 46.8584

    expect(await vault.feeReserves(btc.address)).eq(353); // (117500 - 1) * 0.3% => 353
    expect(await vault.usdvAmounts(btc.address)).eq("46858400000000000000"); // (117500 - 1 - 353) * 40000
    expect(await vault.poolAmounts(btc.address)).eq(117500 - 1 - 353);

    await btc.connect(user0).transfer(vault.address, 117500 - 1);
    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(200),
          true
        )
    ).to.be.revertedWith("Vault: reserve exceeds pool");

    await vault.buyUSDV(btc.address, user1.address);

    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(
      toUsd("93.7168")
    );
    expect(await vlpManager.getAumInUsdv(true)).eq("96059720000000000000"); // 96.05972
    expect(await vlpManager.getAumInUsdv(false)).eq("93716800000000000000"); // 93.7168

    expect(await vault.feeReserves(btc.address)).eq(353 * 2); // (117500 - 1) * 0.3% * 2
    expect(await vault.usdvAmounts(btc.address)).eq("93716800000000000000"); // (117500 - 1 - 353) * 40000 * 2
    expect(await vault.poolAmounts(btc.address)).eq((117500 - 1 - 353) * 2);

    await expect(
      vault
        .connect(user0)
        .increasePosition(
          user0.address,
          btc.address,
          btc.address,
          toUsd(47),
          true
        )
    ).to.be.revertedWith("Vault: insufficient collateral for fees");

    await btc.connect(user0).transfer(vault.address, 22500);

    expect(await vault.reservedAmounts(btc.address)).eq(0);
    expect(await vault.guaranteedUsd(btc.address)).eq(0);

    let position = await vault.getPosition(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(position[0]).eq(0); // size
    expect(position[1]).eq(0); // collateral
    expect(position[2]).eq(0); // averagePrice
    expect(position[3]).eq(0); // entryFundingRate
    expect(position[4]).eq(0); // reserveAmount
    expect(position[5]).eq(0); // realisedPnl
    expect(position[6]).eq(true); // hasProfit
    expect(position[7]).eq(0); // lastIncreasedTime

    const tx = await vault
      .connect(user0)
      .increasePosition(
        user0.address,
        btc.address,
        btc.address,
        toUsd(47),
        true
      );
    await reportGasUsed(tx, "increasePosition gas used");

    const blockTime = await time.latest();

    expect(await vault.poolAmounts(btc.address)).eq(256792 - 114);
    expect(await vault.reservedAmounts(btc.address)).eq(117500);
    expect(await vault.guaranteedUsd(btc.address)).eq(toUsd(38.047));
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(
      toUsd(92.79)
    );
    expect(await vlpManager.getAumInUsdv(true)).eq("95109980000000000000"); // 95.10998
    expect(await vlpManager.getAumInUsdv(false)).eq("93718200000000000000"); // 93.7182

    position = await vault.getPosition(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(position[0]).eq(toUsd(47)); // size
    expect(position[1]).eq(toUsd(8.953)); // collateral, 0.000225 BTC => 9, 9 - 0.047 => 8.953
    expect(position[2]).eq(toNormalizedPrice(41000)); // averagePrice
    expect(position[3]).eq(0); // entryFundingRate
    expect(position[4]).eq(117500); // reserveAmount
    expect(position[5]).eq(0); // realisedPnl
    expect(position[6]).eq(true); // hasProfit
    expect(position[7]).eq(blockTime); // lastIncreasedTime

    expect(await vault.feeReserves(btc.address)).eq(353 * 2 + 114); // fee is 0.047 USD => 0.00000114 BTC
    expect(await vault.usdvAmounts(btc.address)).eq("93716800000000000000"); // (117500 - 1 - 353) * 40000 * 2
    expect(await vault.poolAmounts(btc.address)).eq(
      (117500 - 1 - 353) * 2 + 22500 - 114
    );

    expect(await vault.globalShortSizes(btc.address)).eq(0);
    expect(await vault.globalShortAveragePrices(btc.address)).eq(0);

    await validateVaultBalance(expect, vault, btc);
  });

  it("increasePosition long aum", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(100000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(100000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(100000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await btc.mint(user0.address, expandDecimals(1, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(1, 8));

    expect(await vault.feeReserves(btc.address)).eq(0);
    expect(await vault.usdvAmounts(btc.address)).eq(0);
    expect(await vault.poolAmounts(btc.address)).eq(0);

    expect(await vlpManager.getAumInUsdv(true)).eq(0);
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(0);
    await vault.buyUSDV(btc.address, user1.address);
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(
      toUsd(99700)
    );
    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(99700, 18));

    expect(await vault.feeReserves(btc.address)).eq("300000"); // 0.003 BTC
    expect(await vault.usdvAmounts(btc.address)).eq(expandDecimals(99700, 18));
    expect(await vault.poolAmounts(btc.address)).eq("99700000"); // 0.997

    await btc.mint(user0.address, expandDecimals(5, 7));
    await btc.connect(user0).transfer(vault.address, expandDecimals(5, 7));

    expect(await vault.reservedAmounts(btc.address)).eq(0);
    expect(await vault.guaranteedUsd(btc.address)).eq(0);

    let position = await vault.getPosition(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(position[0]).eq(0); // size
    expect(position[1]).eq(0); // collateral
    expect(position[2]).eq(0); // averagePrice
    expect(position[3]).eq(0); // entryFundingRate
    expect(position[4]).eq(0); // reserveAmount
    expect(position[5]).eq(0); // realisedPnl
    expect(position[6]).eq(true); // hasProfit
    expect(position[7]).eq(0); // lastIncreasedTime

    const tx = await vault
      .connect(user0)
      .increasePosition(
        user0.address,
        btc.address,
        btc.address,
        toUsd(80000),
        true
      );
    await reportGasUsed(tx, "increasePosition gas used");

    const blockTime = await time.latest();

    expect(await vault.poolAmounts(btc.address)).eq("149620000"); // 1.4962 BTC
    expect(await vault.reservedAmounts(btc.address)).eq("80000000"); // 0.8 BTC
    expect(await vault.guaranteedUsd(btc.address)).eq(toUsd(30080)); // 80000 - 49920
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(
      toUsd(99700)
    );
    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(99700, 18));
    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(99700, 18));

    position = await vault.getPosition(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(position[0]).eq(toUsd(80000)); // size
    expect(position[1]).eq(toUsd(49920)); // collateral
    expect(position[2]).eq(toNormalizedPrice(100000)); // averagePrice
    expect(position[3]).eq(0); // entryFundingRate
    expect(position[4]).eq("80000000"); // 0.8 BTC
    expect(position[5]).eq(0); // realisedPnl
    expect(position[6]).eq(true); // hasProfit
    expect(position[7]).eq(blockTime); // lastIncreasedTime

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(150000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(150000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(150000));

    let delta = await vault.getPositionDelta(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(delta[0]).eq(true);
    expect(delta[1]).eq(toUsd(40000));
    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(134510, 18)); // 30080 + (1.4962-0.8)*150000
    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(134510, 18)); // 30080 + (1.4962-0.8)*150000

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(50000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(50000));
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(75000));

    delta = await vault.getPositionDelta(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(delta[0]).eq(false);
    expect(delta[1]).eq(toUsd(40000));
    expect(await vlpManager.getAumInUsdv(true)).eq(expandDecimals(82295, 18)); // 30080 + (1.4962-0.8)*75000
    expect(await vlpManager.getAumInUsdv(false)).eq(expandDecimals(64890, 18)); // 30080 + (1.4962-0.8)*50000

    await vault
      .connect(user0)
      .decreasePosition(
        user0.address,
        btc.address,
        btc.address,
        0,
        toUsd(80000),
        true,
        user2.address
      );

    position = await vault.getPosition(
      user0.address,
      btc.address,
      btc.address,
      true
    );
    expect(position[0]).eq(0); // size
    expect(position[1]).eq(0); // collateral
    expect(position[2]).eq(0); // averagePrice
    expect(position[3]).eq(0); // entryFundingRate
    expect(position[4]).eq(0); // reserveAmount
    expect(position[5]).eq(0); // realisedPnl
    expect(position[6]).eq(true); // hasProfit
    expect(position[7]).eq(0); // lastIncreasedTime

    expect(await vault.poolAmounts(btc.address)).eq("136393334"); // 1.36393334 BTC
    expect(await vault.reservedAmounts(btc.address)).eq(0); // 0.8 BTC
    expect(await vault.guaranteedUsd(btc.address)).eq(toUsd(0));
    expect(await vault.getRedemptionCollateralUsd(btc.address)).eq(
      "68196667000000000000000000000000000"
    );
    expect(await vlpManager.getAumInUsdv(true)).eq("102295000500000000000000"); // 102295.0005
    expect(await vlpManager.getAumInUsdv(false)).eq("68196667000000000000000"); // 68196.667

    expect(await vault.globalShortSizes(btc.address)).eq(0);
    expect(await vault.globalShortAveragePrices(btc.address)).eq(0);

    await validateVaultBalance(expect, vault, btc);
  });
});
