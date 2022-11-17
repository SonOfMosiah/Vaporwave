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

describe("Vault.getFeeBasisPoints", function () {
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

    await vault.setFees(
      50, // _taxBasisPoints
      10, // _stableTaxBasisPoints
      20, // _mintBurnFeeBasisPoints
      30, // _swapFeeBasisPoints
      4, // _stableSwapFeeBasisPoints
      10, // _marginFeeBasisPoints
      toUsd(5), // _liquidationFeeUsd
      0, // _minProfitTime
      true // _hasDynamicFees
    );
  });

  it("getFeeBasisPoints", async () => {
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));
    expect(await vault.getTargetUsdvAmount(bnb.address)).eq(0);

    await bnb.mint(vault.address, 100);
    await vault.connect(user0).buyUSDV(bnb.address, wallet.address);

    expect(await vault.usdvAmounts(bnb.address)).eq(29700);
    expect(await vault.getTargetUsdvAmount(bnb.address)).eq(29700);

    // usdvAmount(bnb) is 29700, targetAmount(bnb) is 29700
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(
      100
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(
      104
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(
      100
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(
      104
    );

    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, true)).eq(
      51
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, true)).eq(
      58
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, false)).eq(
      51
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, false)).eq(
      58
    );

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1));
    await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed));

    expect(await vault.getTargetUsdvAmount(bnb.address)).eq(14850);
    expect(await vault.getTargetUsdvAmount(dai.address)).eq(14850);

    // usdvAmount(bnb) is 29700, targetAmount(bnb) is 14850
    // incrementing bnb has an increased fee, while reducing bnb has a decreased fee
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 20000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(
      50
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(
      50
    );
    expect(
      await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, false)
    ).eq(50);
    expect(
      await vault.getFeeBasisPoints(bnb.address, 20000, 100, 50, false)
    ).eq(50);
    expect(
      await vault.getFeeBasisPoints(bnb.address, 25000, 100, 50, false)
    ).eq(50);
    expect(
      await vault.getFeeBasisPoints(bnb.address, 100000, 100, 50, false)
    ).eq(150);

    await dai.mint(vault.address, 20000);
    await vault.connect(user0).buyUSDV(dai.address, wallet.address);

    expect(await vault.getTargetUsdvAmount(bnb.address)).eq(24850);
    expect(await vault.getTargetUsdvAmount(dai.address)).eq(24850);

    const bnbConfig = getBnbConfig(bnb, bnbPriceFeed);
    bnbConfig[2] = 30000;
    await vault.setTokenConfig(...bnbConfig);

    expect(await vault.getTargetUsdvAmount(bnb.address)).eq(37275);
    expect(await vault.getTargetUsdvAmount(dai.address)).eq(12425);

    expect(await vault.usdvAmounts(bnb.address)).eq(29700);

    // usdvAmount(bnb) is 29700, targetAmount(bnb) is 37270
    // incrementing bnb has a decreased fee, while reducing bnb has an increased fee
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(
      90
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(
      90
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, true)).eq(
      90
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(
      110
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(
      113
    );
    expect(
      await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, false)
    ).eq(116);

    bnbConfig[2] = 5000;
    await vault.setTokenConfig(...bnbConfig);

    await bnb.mint(vault.address, 200);
    await vault.connect(user0).buyUSDV(bnb.address, wallet.address);

    expect(await vault.usdvAmounts(bnb.address)).eq(89100);
    expect(await vault.getTargetUsdvAmount(bnb.address)).eq(36366);
    expect(await vault.getTargetUsdvAmount(dai.address)).eq(72733);

    // usdvAmount(bnb) is 88800, targetAmount(bnb) is 36266
    // incrementing bnb has an increased fee, while reducing bnb has a decreased fee
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 100, 50, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 100, 50, false)).eq(
      28
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 100, 50, false)).eq(
      28
    );
    expect(
      await vault.getFeeBasisPoints(bnb.address, 20000, 100, 50, false)
    ).eq(28);
    expect(
      await vault.getFeeBasisPoints(bnb.address, 50000, 100, 50, false)
    ).eq(28);
    expect(
      await vault.getFeeBasisPoints(bnb.address, 80000, 100, 50, false)
    ).eq(28);

    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 10000, 50, 100, true)).eq(
      150
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 1000, 50, 100, false)).eq(
      0
    );
    expect(await vault.getFeeBasisPoints(bnb.address, 5000, 50, 100, false)).eq(
      0
    );
    expect(
      await vault.getFeeBasisPoints(bnb.address, 20000, 50, 100, false)
    ).eq(0);
    expect(
      await vault.getFeeBasisPoints(bnb.address, 50000, 50, 100, false)
    ).eq(0);
  });
});
