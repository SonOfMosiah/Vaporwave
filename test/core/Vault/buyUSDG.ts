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

describe("Vault.buyUSDV", function () {
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

  it("buyUSDV", async () => {
    await expect(vault.buyUSDV(bnb.address, wallet.address)).to.be.revertedWith(
      "Vault: _token not allowlisted"
    );

    await expect(
      vault.connect(user0).buyUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: _token not allowlisted");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await expect(
      vault.connect(user0).buyUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: invalid tokenAmount");

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);

    await bnb.mint(user0.address, 100);
    await bnb.connect(user0).transfer(vault.address, 100);
    const tx = await vault
      .connect(user0)
      .buyUSDV(bnb.address, user1.address, { gasPrice: "10000000000" });
    await reportGasUsed(tx, "buyUSDV gas used");

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(29700);
    expect(await vault.feeReserves(bnb.address)).eq(1);
    expect(await vault.usdvAmounts(bnb.address)).eq(29700);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1);

    await validateVaultBalance(expect, vault, bnb);

    expect(await vlpManager.getAumInUsdv(true)).eq(29700);
  });

  it("buyUSDV allows gov to mint", async () => {
    await vault.setInManagerMode(true);
    await expect(vault.buyUSDV(bnb.address, wallet.address)).to.be.revertedWith(
      "Vault: forbidden"
    );

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    await bnb.mint(wallet.address, 100);
    await bnb.transfer(vault.address, 100);

    expect(await usdv.balanceOf(wallet.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);

    await expect(
      vault.connect(user0).buyUSDV(bnb.address, wallet.address)
    ).to.be.revertedWith("Vault: forbidden");

    await vault.setManager(user0.address, true);
    await vault.connect(user0).buyUSDV(bnb.address, wallet.address);

    expect(await usdv.balanceOf(wallet.address)).eq(29700);
    expect(await vault.feeReserves(bnb.address)).eq(1);
    expect(await vault.usdvAmounts(bnb.address)).eq(29700);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1);

    await validateVaultBalance(expect, vault, bnb);
  });

  it("buyUSDV uses min price", async () => {
    await expect(
      vault.connect(user0).buyUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: _token not allowlisted");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(200));
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(250));

    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);
    await bnb.mint(user0.address, 100);
    await bnb.connect(user0).transfer(vault.address, 100);
    await vault.connect(user0).buyUSDV(bnb.address, user1.address);
    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(19800);
    expect(await vault.feeReserves(bnb.address)).eq(1);
    expect(await vault.usdvAmounts(bnb.address)).eq(19800);
    expect(await vault.poolAmounts(bnb.address)).eq(100 - 1);

    await validateVaultBalance(expect, vault, bnb);
  });

  it("buyUSDV updates fees", async () => {
    await expect(
      vault.connect(user0).buyUSDV(bnb.address, user1.address)
    ).to.be.revertedWith("Vault: _token not allowlisted");

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(300));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);
    await bnb.mint(user0.address, 10000);
    await bnb.connect(user0).transfer(vault.address, 10000);
    await vault.connect(user0).buyUSDV(bnb.address, user1.address);
    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(9970 * 300);
    expect(await vault.feeReserves(bnb.address)).eq(30);
    expect(await vault.usdvAmounts(bnb.address)).eq(9970 * 300);
    expect(await vault.poolAmounts(bnb.address)).eq(10000 - 30);

    await validateVaultBalance(expect, vault, bnb);
  });

  it("buyUSDV uses mintBurnFeeBasisPoints", async () => {
    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1));
    await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed));

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

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(bnb.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);
    await dai.mint(user0.address, expandDecimals(10000, 18));
    await dai.connect(user0).transfer(vault.address, expandDecimals(10000, 18));
    await vault.connect(user0).buyUSDV(dai.address, user1.address);
    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(
      expandDecimals(10000 - 4, 18)
    );
    expect(await vault.feeReserves(dai.address)).eq(expandDecimals(4, 18));
    expect(await vault.usdvAmounts(dai.address)).eq(
      expandDecimals(10000 - 4, 18)
    );
    expect(await vault.poolAmounts(dai.address)).eq(
      expandDecimals(10000 - 4, 18)
    );
  });

  it("buyUSDV adjusts for decimals", async () => {
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(60000));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await expect(
      vault.connect(user0).buyUSDV(btc.address, user1.address)
    ).to.be.revertedWith("Vault: invalid tokenAmount");

    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await usdv.balanceOf(user1.address)).eq(0);
    expect(await vault.feeReserves(btc.address)).eq(0);
    expect(await vault.usdvAmounts(bnb.address)).eq(0);
    expect(await vault.poolAmounts(bnb.address)).eq(0);
    await btc.mint(user0.address, expandDecimals(1, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(1, 8));
    await vault.connect(user0).buyUSDV(btc.address, user1.address);
    expect(await usdv.balanceOf(user0.address)).eq(0);
    expect(await vault.feeReserves(btc.address)).eq(300000);
    expect(await usdv.balanceOf(user1.address)).eq(
      expandDecimals(60000, 18).sub(expandDecimals(180, 18))
    ); // 0.3% of 60,000 => 180
    expect(await vault.usdvAmounts(btc.address)).eq(
      expandDecimals(60000, 18).sub(expandDecimals(180, 18))
    );
    expect(await vault.poolAmounts(btc.address)).eq(
      expandDecimals(1, 8).sub(300000)
    );

    await validateVaultBalance(expect, vault, btc);
  });
});
