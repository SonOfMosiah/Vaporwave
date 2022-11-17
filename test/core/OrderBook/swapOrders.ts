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
import {
  getDefault,
  validateOrderFields,
  getTxFees,
  positionWrapper,
  defaultCreateIncreaseOrderFactory,
  defaultCreateDecreaseOrderFactory,
  defaultCreateSwapOrderFactory,
  getTriggerRatio,
  getMinOut,
} from "./helpers";

const BTC_PRICE = 60000;
const BNB_PRICE = 300;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const PRICE_PRECISION = ethers.BigNumber.from(10).pow(30);
const BASIS_POINTS_DIVISOR = 10000;

describe("OrderBook, swap orders", function () {
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
      [bnb.address]: 18,
      [dai.address]: 18,
      [usdv.address]: 18,
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

    // it's impossible to just mint usdv (?)
    await router
      .connect(user0)
      .swap(
        [dai.address, usdv.address],
        expandDecimals(10000, 18),
        expandDecimals(9900, 18),
        user0.address
      );
    await usdv.connect(user0).approve(router.address, expandDecimals(9900, 18));

    await btc.mint(user0.address, expandDecimals(1000, 8));
    await btc.connect(user0).transfer(vault.address, expandDecimals(100, 8));
    await vault.directPoolDeposit(btc.address);

    await bnb.mint(user0.address, expandDecimals(100000, 18));
    await bnb.connect(user0).approve(router.address, expandDecimals(50000, 18));

    await bnb.connect(user0).transfer(vault.address, expandDecimals(10000, 18));
    await vault.directPoolDeposit(bnb.address);
    // probably I'm doing something wrong? contract doesn't have enough funds
    // when I need to withdraw weth (which I have in balances)
    await bnb.deposit({ value: expandDecimals(500, 18) });

    defaults = {
      path: [dai.address, btc.address],
      sizeDelta: toUsd(100000),
      minOut: 0,
      amountIn: expandDecimals(1000, 18),
      triggerPrice: toUsd(53000),
      triggerAboveThreshold: true,
      executionFee: expandDecimals(1, 9).mul(1500000),
      collateralToken: btc.address,
      collateralDelta: toUsd(BTC_PRICE),
      user: user0,
      isLong: true,
      shouldWrap: false,
      shouldUnwrap: true,
    };
    defaultCreateSwapOrder = defaultCreateSwapOrderFactory(
      orderBook,
      defaults,
      tokenDecimals
    );
  });

  async function getCreatedSwapOrder(address: string, orderIndex = 0) {
    const order = await orderBook.swapOrders(address, orderIndex);
    return order;
  }

  /*
    checklist:
    [x] create order, path.length not in (2, 3) => revert
    [x] create order, path[0] == path[-1] => revert
    [x] executionFee less than minimum =< revert
    [x] if path[0] == weth -> transfer fee + amountIn
    [x] transferred token == amountIn
    [x] and check total transfer, otherwise revert
    [x] if path[0] != weth -> transfer fee and transfer token separately
    [x] and check total transfer, otherwise => revert
    [x] order retreivable
    [x] two orders retreivable
    [x] cancel order deletes order
    [x] and returns amountIn as token + fees as BNB if path[0] != weth
    [x] otherwise returns fees + amountIn as BNB
    [x] execute order – revert if doest not exist
    [x] if trigger below and minOut insufficient -> revert
    [x] if trigger above and priceRatio is incorrect -> revert
    [x] if priceRatio correct but minOut insufficient -> revert
    [x] if coniditions are met executor receives fee
    [x] user receives BNB if path[-1] == weth
    [x] or token otherwise
    [x] order is deleted after execution
    [x] user can update minOut, triggerRatio and triggerAboveThreshold
    [x] if order doesn't exist => revert
    */

  it("createSwapOrder, bad input", async () => {
    await expect(
      defaultCreateSwapOrder({
        path: [btc.address],
        triggerRatio: 1,
      }),
      "1"
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");

    await expect(
      defaultCreateSwapOrder({
        path: [btc.address, btc.address, dai.address, dai.address],
        triggerRatio: 1,
      }),
      "2"
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");

    await expect(
      defaultCreateSwapOrder({
        path: [btc.address, bnb.address],
        triggerRatio: 1,
        shouldWrap: true,
      })
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");

    await expect(
      defaultCreateSwapOrder({
        path: [btc.address, btc.address],
        triggerRatio: 1,
      }),
      "3"
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");

    await expect(
      defaultCreateSwapOrder({
        path: [dai.address, btc.address],
        triggerRatio: 1,
        executionFee: 100,
      }),
      "4"
    ).to.be.revertedWithCustomError(orderBook, "InsufficientFee");

    await expect(
      defaultCreateSwapOrder({
        path: [dai.address, btc.address],
        triggerRatio: 1,
        value: 100,
      }),
      "5"
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");
  });

  it("createSwapOrder, DAI -> BTC", async () => {
    const triggerRatio = toUsd(1).mul(PRICE_PRECISION).div(toUsd(58000));
    const userDaiBalanceBefore = await dai.balanceOf(defaults.user.address);
    const [tx, props] = await defaultCreateSwapOrder({
      triggerRatio,
      triggerAboveThreshold: false,
    });
    reportGasUsed(tx, "createSwapOrder");
    const userDaiBalanceAfter = await dai.balanceOf(defaults.user.address);
    expect(userDaiBalanceAfter).to.be.equal(
      userDaiBalanceBefore.sub(defaults.amountIn)
    );

    const daiBalance = await dai.balanceOf(orderBook.address);
    expect(daiBalance).to.be.equal(defaults.amountIn);
    const bnbBalance = await bnb.balanceOf(orderBook.address);
    expect(bnbBalance).to.be.equal(defaults.executionFee);

    const order = await getCreatedSwapOrder(defaults.user.address);

    validateOrderFields(order, {
      account: defaults.user.address,
      triggerRatio,
      triggerAboveThreshold: false,
      path: [dai.address, btc.address],
      minOut: props.minOut,
      amountIn: defaults.amountIn,
      executionFee: defaults.executionFee,
    });
  });

  it("createSwapOrder, WBNB -> DAI", async () => {
    const triggerRatio = getTriggerRatio(toUsd(550), toUsd(1));
    const amountIn = expandDecimals(10, 18);

    await expect(
      defaultCreateSwapOrder({
        path: [bnb.address, dai.address],
        triggerRatio,
        triggerAboveThreshold: false,
        amountIn,
        value: defaults.executionFee.sub(1),
      })
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    await expect(
      defaultCreateSwapOrder({
        path: [bnb.address, dai.address],
        triggerRatio,
        triggerAboveThreshold: false,
        amountIn,
        value: defaults.executionFee.add(1),
      })
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    let tx, props;
    [tx, props] = await defaultCreateSwapOrder({
      path: [bnb.address, dai.address],
      triggerRatio,
      triggerAboveThreshold: false,
      amountIn,
      value: defaults.executionFee,
    });
    reportGasUsed(tx, "createSwapOrder");
    const bnbBalance = await bnb.balanceOf(orderBook.address);
    expect(bnbBalance).to.be.equal(defaults.executionFee.add(amountIn));

    const order = await getCreatedSwapOrder(defaults.user.address);

    validateOrderFields(order, {
      account: defaults.user.address,
      triggerRatio,
      triggerAboveThreshold: false,
      path: [dai.address, btc.address],
      minOut: props.minOut,
      executionFee: defaults.executionFee,
      amountIn,
    });
  });

  it("createSwapOrder, BNB -> DAI", async () => {
    const triggerRatio = getTriggerRatio(toUsd(550), toUsd(1));
    const amountIn = expandDecimals(10, 18);
    const value = defaults.executionFee.add(amountIn);

    await expect(
      defaultCreateSwapOrder({
        path: [bnb.address, dai.address],
        triggerRatio,
        triggerAboveThreshold: false,
        amountIn,
        shouldWrap: true,
        value: value.sub(1),
      })
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    await expect(
      defaultCreateSwapOrder({
        path: [bnb.address, dai.address],
        triggerRatio,
        triggerAboveThreshold: false,
        amountIn,
        shouldWrap: true,
        value: value.add(1),
      })
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    let tx, props;
    [tx, props] = await defaultCreateSwapOrder({
      path: [bnb.address, dai.address],
      triggerRatio,
      triggerAboveThreshold: false,
      shouldWrap: true,
      amountIn,
      value,
    });
    reportGasUsed(tx, "createSwapOrder");
    const bnbBalance = await bnb.balanceOf(orderBook.address);
    expect(bnbBalance).to.be.equal(value);

    const order = await getCreatedSwapOrder(defaults.user.address);

    validateOrderFields(order, {
      account: defaults.user.address,
      triggerRatio,
      triggerAboveThreshold: false,
      path: [dai.address, btc.address],
      minOut: props.minOut,
      executionFee: defaults.executionFee,
      amountIn,
    });
  });

  it("createSwapOrder, DAI -> WBNB, shouldUnwrap = false", async () => {
    const triggerRatio = getTriggerRatio(toUsd(1), toUsd(310));
    const amountIn = expandDecimals(100, 18);

    let tx, props;
    [tx, props] = await defaultCreateSwapOrder({
      path: [dai.address, bnb.address],
      triggerRatio,
      triggerAboveThreshold: false,
      amountIn,
      shouldUnwrap: false,
      value: defaults.executionFee,
    });
    reportGasUsed(tx, "createSwapOrder");

    const order = await getCreatedSwapOrder(defaults.user.address);

    validateOrderFields(order, {
      account: defaults.user.address,
      triggerRatio,
      triggerAboveThreshold: false,
      path: [dai.address, btc.address],
      minOut: props.minOut,
      executionFee: defaults.executionFee,
      shouldUnwrap: false,
      amountIn,
    });
  });

  it("createSwapOrder, two orders", async () => {
    const triggerRatio1 = getTriggerRatio(toUsd(58000), toUsd(1));
    let tx1;
    [tx1] = await defaultCreateSwapOrder({ triggerRatio: triggerRatio1 });
    reportGasUsed(tx1, "createSwapOrder");

    const triggerRatio2 = getTriggerRatio(toUsd(59000), toUsd(1));
    let tx2;
    [tx2] = await defaultCreateSwapOrder({ triggerRatio: triggerRatio2 });
    reportGasUsed(tx2, "createSwapOrder");

    const order1 = await getCreatedSwapOrder(defaults.user.address, 0);
    const order2 = await getCreatedSwapOrder(defaults.user.address, 1);

    expect(order1.account).to.be.equal(defaults.user.address);
    expect(order1.triggerRatio).to.be.equal(triggerRatio1);

    expect(order2.account).to.be.equal(defaults.user.address);
    expect(order2.triggerRatio).to.be.equal(triggerRatio2);
  });

  it("cancelSwapOrder, tokenA != BNB", async () => {
    const triggerRatio = toUsd(58000).mul(PRICE_PRECISION).div(toUsd(1));
    await defaultCreateSwapOrder({
      triggerRatio,
      triggerAboveThreshold: false,
    });

    const balanceBefore = await defaults.user.getBalance();
    const daiBalanceBefore = await dai.balanceOf(defaults.user.address);

    const tx = await orderBook.connect(defaults.user).cancelSwapOrder(0);
    reportGasUsed(tx, "canceSwapOrder");
    const txFees = await getTxFees(tx);

    const balanceAfter = await user0.getBalance();
    const daiBalanceAfter = await dai.balanceOf(defaults.user.address);
    const order = await getCreatedSwapOrder(defaults.user.address);

    expect(balanceAfter, "balanceAfter").to.be.equal(
      balanceBefore.add(defaults.executionFee).sub(txFees)
    );
    expect(daiBalanceAfter, "daiBalanceAfter").to.be.eq(
      daiBalanceBefore.add(defaults.amountIn)
    );

    expect(order.account, "account").to.be.equal(ZERO_ADDRESS);
  });

  it("cancelSwapOrder, tokenA == BNB", async () => {
    const triggerRatio = toUsd(1).mul(PRICE_PRECISION).div(toUsd(550));
    const amountIn = expandDecimals(10, 18);
    const value = defaults.executionFee.add(amountIn);
    await defaultCreateSwapOrder({
      path: [bnb.address, dai.address],
      triggerRatio,
      triggerAboveThreshold: false,
      amountIn,
      shouldWrap: true,
      value,
    });

    const balanceBefore = await defaults.user.getBalance();

    const tx = await orderBook.connect(defaults.user).cancelSwapOrder(0);
    reportGasUsed(tx, "canceSwapOrder");
    const txFees = await getTxFees(tx);

    const balanceAfter = await user0.getBalance();
    const order = await getCreatedSwapOrder(defaults.user.address);

    expect(balanceAfter, "balanceAfter").to.be.equal(
      balanceBefore.add(value).sub(txFees)
    );

    expect(order.account, "account").to.be.equal(ZERO_ADDRESS);
  });

  it("updateSwapOrder", async () => {
    const triggerRatio = toUsd(58000).mul(PRICE_PRECISION).div(toUsd(1));
    await defaultCreateSwapOrder({
      triggerRatio,
    });

    const orderBefore = await getCreatedSwapOrder(defaults.user.address);

    validateOrderFields(orderBefore, {
      triggerRatio,
      triggerAboveThreshold: defaults.triggerAboveThreshold,
      minOut: defaults.minOut,
    });

    const newTriggerRatio = toUsd(58000).mul(PRICE_PRECISION).div(toUsd(1));
    const newTriggerAboveThreshold = !defaults.triggerAboveThreshold;
    const newMinOut = expandDecimals(1, 8).div(1000);

    await expect(
      orderBook
        .connect(user1)
        .updateSwapOrder(
          0,
          newMinOut,
          newTriggerRatio,
          newTriggerAboveThreshold
        )
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    await expect(
      orderBook
        .connect(defaults.user)
        .updateSwapOrder(
          1,
          newMinOut,
          newTriggerRatio,
          newTriggerAboveThreshold
        )
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    const tx = await orderBook
      .connect(defaults.user)
      .updateSwapOrder(0, newMinOut, newTriggerRatio, newTriggerAboveThreshold);
    reportGasUsed(tx, "updateSwapOrder");

    const orderAfter = await getCreatedSwapOrder(defaults.user.address);
    validateOrderFields(orderAfter, {
      triggerRatio: newTriggerRatio,
      triggerAboveThreshold: newTriggerAboveThreshold,
      minOut: newMinOut,
    });
  });

  it("executeSwapOrder, triggerAboveThreshold == false", async () => {
    // in this case contract OrderBook will ignore triggerPrice prop
    // and will try to swap using passed minOut
    // minOut will ensure swap will occur with suitable price

    const amountIn = expandDecimals(1, 8);
    const value = defaults.executionFee;
    const path = [btc.address, bnb.address];
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(BTC_PRICE), toUsd(BNB_PRICE - 50)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path,
      triggerAboveThreshold: false,
      amountIn,
      minOut,
      value,
    });

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, user1.address),
      "non-existent order"
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    bnbPriceFeed.setLatestAnswer(toChainlinkPrice(BNB_PRICE - 30));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, user1.address),
      "insufficient amountOut"
    ).to.be.revertedWithCustomError(orderBook, "InsufficientAmountOut");

    bnbPriceFeed.setLatestAnswer(toChainlinkPrice(BNB_PRICE - 70));

    const executor = user1;
    const executorBalanceBefore = await executor.getBalance();
    const userBalanceBefore = await defaults.user.getBalance();

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await executor.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userBalanceAfter = await defaults.user.getBalance();
    expect(
      userBalanceAfter.gt(userBalanceBefore.add(minOut)),
      "userBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == false, DAI -> WBNB, shouldUnwrap = false", async () => {
    const amountIn = expandDecimals(100, 18);
    const value = defaults.executionFee;
    const path = [dai.address, bnb.address];
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(1), toUsd(BNB_PRICE + 50)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path,
      triggerAboveThreshold: false,
      amountIn,
      minOut,
      shouldUnwrap: false,
      value,
    });

    const executor = user1;
    const executorBalanceBefore = await executor.getBalance();
    const userWbnbBalanceBefore = await bnb.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await executor.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userWbnbBalanceAfter = await bnb.balanceOf(defaults.user.address);
    expect(
      userWbnbBalanceAfter.gt(userWbnbBalanceBefore.add(minOut)),
      "userWbnbBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == true", async () => {
    const triggerRatio = getTriggerRatio(toUsd(BNB_PRICE), toUsd(62000));
    const amountIn = expandDecimals(10, 18);
    const path = [bnb.address, btc.address];
    const value = defaults.executionFee.add(amountIn);

    // minOut is not mandatory for such orders but with minOut it's possible to limit max price
    // e.g. user would not be happy if he sets order "buy if BTC > $65000" and order executes with $75000
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(BNB_PRICE), toUsd(63000)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path: path,
      minOut,
      triggerRatio,
      shouldWrap: true,
      triggerAboveThreshold: true,
      amountIn,
      value,
    });

    const executor = user1;

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(60500));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(62500));

    const executorBalanceBefore = await executor.getBalance();
    const userBtcBalanceBefore = await btc.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userBtcBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(
      userBtcBalanceAfter.gt(userBtcBalanceBefore.add(minOut)),
      "userBtcBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == true, BNB -> DAI -> BTC", async () => {
    const triggerRatio = getTriggerRatio(toUsd(BNB_PRICE), toUsd(62000));
    const amountIn = expandDecimals(10, 18);
    const path = [bnb.address, dai.address, btc.address];
    const value = defaults.executionFee.add(amountIn);

    // minOut is not mandatory for such orders but with minOut it's possible to limit max price
    // e.g. user would not be happy if he sets order "buy if BTC > $65000" and order executes with $75000
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(BNB_PRICE), toUsd(63000)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path: path,
      minOut,
      triggerRatio,
      shouldWrap: true,
      triggerAboveThreshold: true,
      amountIn,
      value,
    });

    const executor = user1;

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(60500));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(62500));

    const executorBalanceBefore = await executor.getBalance();
    const userBtcBalanceBefore = await btc.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userBtcBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(
      userBtcBalanceAfter.gt(userBtcBalanceBefore.add(minOut)),
      "userBtcBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == true, USDV -> BTC", async () => {
    const triggerRatio = getTriggerRatio(toUsd(1), toUsd(62000));
    const amountIn = expandDecimals(1000, 18);
    const path = [usdv.address, btc.address];
    const value = defaults.executionFee;

    // minOut is not mandatory for such orders but with minOut it's possible to limit max price
    // e.g. user would not be happy if he sets order "buy if BTC > $65000" and order executes with $75000
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(1), toUsd(63000)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path,
      minOut,
      triggerRatio,
      triggerAboveThreshold: true,
      amountIn,
      value,
    });

    const executor = user1;

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(60500));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(70000));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InsufficientAmountOut");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(62500));

    const executorBalanceBefore = await executor.getBalance();
    const userBtcBalanceBefore = await btc.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userBtcBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(
      userBtcBalanceAfter.gt(userBtcBalanceBefore.add(minOut)),
      "userBtcBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == true, USDV -> DAI -> BTC", async () => {
    const triggerRatio = getTriggerRatio(toUsd(1), toUsd(62000));
    const amountIn = expandDecimals(1000, 18);
    const path = [usdv.address, dai.address, btc.address];
    const value = defaults.executionFee;

    // minOut is not mandatory for such orders but with minOut it's possible to limit max price
    // e.g. user would not be happy if he sets order "buy if BTC > $65000" and order executes with $75000
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(1), toUsd(63000)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path,
      minOut,
      triggerRatio,
      triggerAboveThreshold: true,
      amountIn,
      value,
    });

    const executor = user1;

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(60500));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(70000));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InsufficientAmountOut");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(62500));

    const executorBalanceBefore = await executor.getBalance();
    const userBtcBalanceBefore = await btc.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userBtcBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(
      userBtcBalanceAfter.gt(userBtcBalanceBefore.add(minOut)),
      "userBtcBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == true, USDV -> BNB -> BTC", async () => {
    const triggerRatio = getTriggerRatio(toUsd(1), toUsd(62000));
    const amountIn = expandDecimals(1000, 18);
    const path = [usdv.address, bnb.address, btc.address];
    const value = defaults.executionFee;

    // minOut is not mandatory for such orders but with minOut it's possible to limit max price
    // e.g. user would not be happy if he sets order "buy if BTC > $65000" and order executes with $75000
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(1), toUsd(63000)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path,
      minOut,
      triggerRatio,
      triggerAboveThreshold: true,
      amountIn,
      value,
    });

    const executor = user1;

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(60500));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(70000));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InsufficientAmountOut");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(62500));

    const executorBalanceBefore = await executor.getBalance();
    const userBtcBalanceBefore = await btc.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userBtcBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(
      userBtcBalanceAfter.gt(userBtcBalanceBefore.add(minOut)),
      "userBtcBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeSwapOrder, triggerAboveThreshold == true, BTC -> USDV", async () => {
    const triggerRatio = getTriggerRatio(toUsd(62000), toUsd(1));
    const amountIn = expandDecimals(1, 6); // 0.01 BTC
    const path = [btc.address, usdv.address];
    const value = defaults.executionFee;

    // minOut is not mandatory for such orders but with minOut it's possible to limit max price
    // e.g. user would not be happy if he sets order "buy if BTC > $65000" and order executes with $75000
    const minOut = await getMinOut(
      tokenDecimals,
      getTriggerRatio(toUsd(60000), toUsd(1)),
      path,
      amountIn
    );

    await defaultCreateSwapOrder({
      path,
      minOut,
      triggerRatio,
      triggerAboveThreshold: true,
      amountIn,
      value,
    });

    const executor = user1;

    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 2, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(63000));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(50000));
    await expect(
      orderBook.executeSwapOrder(defaults.user.address, 0, executor.address)
    ).to.be.revertedWithCustomError(orderBook, "InsufficientAmountOut");

    btcPriceFeed.setLatestAnswer(toChainlinkPrice(61000));

    const executorBalanceBefore = await executor.getBalance();
    const userUsdvBalanceBefore = await usdv.balanceOf(defaults.user.address);

    const tx = await orderBook.executeSwapOrder(
      defaults.user.address,
      0,
      executor.address
    );
    reportGasUsed(tx, "executeSwapOrder");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter, "executorBalanceAfter").to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const userUsdvBalanceAfter = await usdv.balanceOf(defaults.user.address);
    expect(
      userUsdvBalanceAfter.gt(userUsdvBalanceBefore.add(minOut)),
      "userUsdvBalanceAfter"
    ).to.be.true;

    const order = await getCreatedSwapOrder(defaults.user.address, 0);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("complex scenario", async () => {
    const triggerRatio1 = toUsd(BTC_PRICE + 2000)
      .mul(PRICE_PRECISION)
      .div(toUsd(1));
    const order1Index = 0;
    // buy BTC with DAI when BTC price goes up
    let props1;
    [, props1] = await defaultCreateSwapOrder({
      path: [dai.address, btc.address],
      triggerRatio: triggerRatio1,
      triggerAboveThreshold: true,
    });

    // buy BTC with BNB when BTC price goes up
    let triggerRatio2 = toUsd(BTC_PRICE - 5000)
      .mul(PRICE_PRECISION)
      .div(toUsd(BNB_PRICE));
    const order2Index = 1;
    const amountIn = expandDecimals(5, 18);
    const value = defaults.executionFee.add(amountIn);
    await defaultCreateSwapOrder({
      path: [bnb.address, btc.address],
      triggerRatio: triggerRatio2,
      triggerAboveThreshold: false,
      amountIn,
      shouldWrap: true,
      value,
    });

    // buy BTC with BNB when BTC price goes up
    let triggerRatio3 = toUsd(BTC_PRICE - 5000)
      .mul(PRICE_PRECISION)
      .div(toUsd(BNB_PRICE));
    const order3Index = 2;
    let props3;
    [, props3] = await defaultCreateSwapOrder({
      path: [dai.address, btc.address],
      triggerRatio: triggerRatio3,
      triggerAboveThreshold: false,
    });

    // try to execute order 1
    await btcPriceFeed.setLatestAnswer(toChainlinkPrice(BTC_PRICE + 1500));
    await expect(
      orderBook.executeSwapOrder(
        defaults.user.address,
        order1Index,
        user1.address
      ),
      "order1 revert"
    ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

    // update order 1
    const newTriggerRatio1 = toUsd(BTC_PRICE + 1000)
      .mul(PRICE_PRECISION)
      .div(toUsd(1));
    await orderBook
      .connect(defaults.user)
      .updateSwapOrder(order1Index, props1.minOut, newTriggerRatio1, true);
    let order1 = await getCreatedSwapOrder(defaults.user.address, order1Index);
    expect(order1.triggerRatio, "order1 triggerRatio").to.be.equal(
      newTriggerRatio1
    );

    //  execute order 1
    await orderBook.executeSwapOrder(
      defaults.user.address,
      order1Index,
      user1.address
    );
    order1 = await getCreatedSwapOrder(defaults.user.address, order1Index);
    expect(order1.account, "order1 account").to.be.equal(ZERO_ADDRESS);

    // cancel order 3
    let btcBalanceBefore = await btc.balanceOf(defaults.user.address);
    await orderBook.connect(defaults.user).cancelSwapOrder(order3Index);
    let order3 = await getCreatedSwapOrder(defaults.user.address, order3Index);
    expect(order3.account, "order3 account").to.be.equal(ZERO_ADDRESS);

    let btcBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(
      btcBalanceAfter.gt(btcBalanceBefore.add(props3.minOut)),
      "btcBalanceBefore"
    );

    // try to execute order 2
    await expect(
      orderBook.executeSwapOrder(
        defaults.user.address,
        order2Index,
        user1.address
      ),
      "order2 revert"
    ).to.be.revertedWithCustomError(orderBook, "InsufficientAmountOut");

    // execute order 2
    await bnbPriceFeed.setLatestAnswer(toChainlinkPrice(BNB_PRICE + 100)); // BTC price decreased relative to BNB
    await orderBook.executeSwapOrder(
      defaults.user.address,
      order2Index,
      user1.address
    );
    let order2 = await getCreatedSwapOrder(defaults.user.address, order2Index);
    expect(order2.account, "order2 account").to.be.equal(ZERO_ADDRESS);
  });
});
