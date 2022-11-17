import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContract } from "../../shared/fixtures";
import { time, mine } from "@nomicfoundation/hardhat-network-helpers";
import { expandDecimals, reportGasUsed, gasUsed } from "../../shared/utilities";
import { toChainlinkPrice } from "../../shared/chainlink";
import { toUsd, toNormalizedPrice } from "../../shared/units";
import {
  initVault,
  getBnbConfig,
  getEthConfig,
  getBtcConfig,
  getDaiConfig,
  validateVaultBalance,
} from "../Vault/helpers";

const BTC_PRICE = 60000;
const BNB_PRICE = 300;

describe("OrderBook", function () {
  let wallet: any, user0: any, user1: any, user2: any, user3: any;

  let defaults: any;
  let orderBook: any;
  let increaseOrderDefaults: any;
  let decreaseOrderDefaults: any;
  let swapOrderDefaults: any;
  let tokenDecimals: any;
  let defaultCreateIncreaseOrder: any;
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
  let busd: any;
  let busdPriceFeed: any;
  let vaultPriceFeed: any;
  let vault: any;
  let distributor0: any;
  let yieldTracker0: any;
  let reader: any;
  let defaultCreateDecreaseOrder: any;
  let defaultCreateSwapOrder: any;

  before(async () => {
    [wallet, user0, user1, user2, user3] = await ethers.getSigners();
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
    await vaultPriceFeed.setPriceSampleSpace(1);

    tokenDecimals = {
      [bnb.address]: 8,
      [dai.address]: 18,
      [btc.address]: 8,
    };

    await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1));
    await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed));

    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(BTC_PRICE));
    await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed));

    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(BNB_PRICE));
    await vault.setTokenConfig(...getBnbConfig(bnb, bnbPriceFeed));

    orderBook = await deployContract("OrderBook", []);
    const minExecutionFee = 500000;
    await orderBook.initialize(
      router.address,
      vault.address,
      bnb.address,
      usdv.address,
      minExecutionFee,
      expandDecimals(5, 30) // minPurchseTokenAmountUsd
    );

    await router.addPlugin(orderBook.address);
    await router.connect(user0).approvePlugin(orderBook.address);

    await btc.mint(user0.address, expandDecimals(1000, 8));
    await btc.connect(user0).approve(router.address, expandDecimals(100, 8));

    await dai.mint(user0.address, expandDecimals(10000000, 18));
    await dai
      .connect(user0)
      .approve(router.address, expandDecimals(1000000, 18));

    await dai.mint(user0.address, expandDecimals(20000000, 18));
    await dai
      .connect(user0)
      .transfer(vault.address, expandDecimals(2000000, 18));
    await vault.directPoolDeposit(dai.address);

    await btc.mint(user0.address, expandDecimals(1000, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(100, 8));
    await vault.directPoolDeposit(btc.address);

    await bnb.mint(user0.address, expandDecimals(10000, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(10000, 18));
    await vault.directPoolDeposit(bnb.address);
  });

  it("transferOwnership", async () => {
    await expect(
      orderBook.connect(user0).transferOwnership(user1.address)
    ).to.be.revertedWithCustomError(orderBook, "OrderBookForbidden");

    expect(await orderBook.owner()).eq(wallet.address);

    await orderBook.transferOwnership(user0.address);
    expect(await orderBook.owner()).eq(user0.address);

    await orderBook.connect(user0).transferOwnership(user1.address);
    expect(await orderBook.owner()).eq(user1.address);
  });

  it("set*", async () => {
    const cases = [
      ["setMinExecutionFee", 600000],
      ["setMinPurchaseTokenAmountUsd", 1],
    ];
    for (const [name, arg] of cases) {
      await expect(orderBook.connect(user1)[name](arg)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      await expect(orderBook[name](arg));
    }
  });

  it("initialize, already initialized", async () => {
    await expect(
      orderBook.connect(user1).initialize(
        router.address,
        vault.address,
        bnb.address,
        usdv.address,
        1,
        expandDecimals(5, 30) // minPurchseTokenAmountUsd
      )
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await expect(
      orderBook.initialize(
        router.address,
        vault.address,
        bnb.address,
        usdv.address,
        1,
        expandDecimals(5, 30) // minPurchseTokenAmountUsd
      )
    ).to.be.revertedWithCustomError(orderBook, "AlreadyInitialized");
  });
});
