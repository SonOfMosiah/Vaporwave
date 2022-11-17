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
} from "./helpers";

const BTC_PRICE = 60000;
const BNB_PRICE = 300;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const PRICE_PRECISION = ethers.BigNumber.from(10).pow(30);
const BASIS_POINTS_DIVISOR = 10000;

describe("OrderBook, increase position orders", function () {
  /*
    checklist:
    create order
    - [x] revert if fee too low
    - [x] revert if fee != transferred BNB (if not WETH)
    - [x] revert if fee + amountIn  != transferred BNB (if WETH)
    - [x] transfer execution fee
    - [x] transfer token to OrderBook (if transfer token != WETH)
    - [x] transfer execution fee + amount with BNB (if WETH)
    - [x] swap tokens if path.length > 1
    - [x] revert if path.length > 3
    - [x] revert if transferred collateral usd is too low
    - [x] create order with provided fields
    cancel order
    - [x] revert if order doesn't exist
    - [x] delete order
    - [x] transfer BNB if WETH
    - [x] transfer BNB and token if not WETH
    update
    - [x] revert if does not exist
    - [x] update all fields provided
    execute
    - [x] revert if does not exist
    - [x] revert if price invalid
        - [x] currentPrice < triggerPrice && triggerAboveThreshold is true
        - [x] currentPrice > triggerPrice && triggerAboveThreshold is false
    - [x] delete order
    - [x] open position
        - [x] position.collateral == order.collateral
        - [x] position.size == order.sizeDelta (if new)
        - [x] position.size == order.sizeDelta + positionBefore.size (if not new)
    - [x] pay fees to executor
    */

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

    await bnb.mint(user0.address, expandDecimals(10000000, 18));
    await bnb
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

    await bnb.mint(user0.address, expandDecimals(50000, 18));
    await bnb.connect(user0).transfer(vault.address, expandDecimals(10000, 18));
    await vault.directPoolDeposit(bnb.address);

    defaults = {
      path: [btc.address],
      sizeDelta: toUsd(100000),
      amountIn: expandDecimals(1, 8),
      minOut: 0,
      triggerPrice: toUsd(53000),
      triggerAboveThreshold: true,
      executionFee: expandDecimals(1, 9).mul(1500000),
      collateralToken: btc.address,
      collateralDelta: toUsd(BTC_PRICE),
      user: user0,
      isLong: true,
      shouldWrap: false,
    };

    defaultCreateIncreaseOrder = defaultCreateIncreaseOrderFactory(
      orderBook,
      defaults
    );
  });

  async function getCreatedIncreaseOrder(address: string, orderIndex = 0) {
    const order = await orderBook.increaseOrders(address, orderIndex);
    return order;
  }

  it("createIncreaseOrder, bad input", async () => {
    const lowExecutionFee = 100;
    let counter = 0;
    await expect(
      defaultCreateIncreaseOrder({
        executionFee: lowExecutionFee,
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InsufficientFee");

    const goodExecutionFee: any = expandDecimals(1, 8);
    await expect(
      defaultCreateIncreaseOrder({
        executionFee: goodExecutionFee,
        value: goodExecutionFee - 1,
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");
    await expect(
      defaultCreateIncreaseOrder({
        executionFee: goodExecutionFee,
        value: goodExecutionFee + 1,
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    await expect(
      defaultCreateIncreaseOrder({
        path: [bnb.address],
        executionFee: goodExecutionFee,
        value: expandDecimals(10, 8).add(goodExecutionFee).sub(1),
        shouldWrap: true,
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    await expect(
      defaultCreateIncreaseOrder({
        path: [btc.address],
        executionFee: goodExecutionFee,
        value: expandDecimals(10, 8).add(goodExecutionFee),
        shouldWrap: true,
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");

    await expect(
      defaultCreateIncreaseOrder({
        path: [bnb.address],
        executionFee: goodExecutionFee,
        amountIn: expandDecimals(10, 8),
        value: expandDecimals(10, 8).add(goodExecutionFee),
        shouldWrap: false,
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InvalidValue");

    await expect(
      defaultCreateIncreaseOrder({
        path: [dai.address],
        amountIn: expandDecimals(4, 18),
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InsufficientCollateral");

    await expect(
      defaultCreateIncreaseOrder({
        path: [dai.address, btc.address, bnb.address, btc.address],
        amountIn: expandDecimals(4, 18),
      }),
      (counter++).toString()
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");
  });

  it("createIncreaseOrder, two orders", async () => {
    const sizeDelta1 = toUsd(40000);
    await defaultCreateIncreaseOrder({
      path: [btc.address],
      amountIn: expandDecimals(1, 8).div(10),
      sizeDelta: sizeDelta1,
    });
    const sizeDelta2 = toUsd(50000);
    await defaultCreateIncreaseOrder({
      path: [btc.address],
      amountIn: expandDecimals(1, 8).div(10),
      sizeDelta: sizeDelta2,
    });

    const order1 = await getCreatedIncreaseOrder(defaults.user.address, 0);
    const order2 = await getCreatedIncreaseOrder(defaults.user.address, 1);

    expect(order1.sizeDelta).to.be.equal(sizeDelta1);
    expect(order2.sizeDelta).to.be.equal(sizeDelta2);
  });

  it("createIncreaseOrder, pay WETH", async () => {
    const bnbBalanceBefore = await bnb.balanceOf(orderBook.address);
    const amountIn = expandDecimals(30, 18);
    const value = defaults.executionFee;
    const tx = await defaultCreateIncreaseOrder({
      path: [bnb.address],
      amountIn,
      value,
      shouldWrap: false,
    });

    reportGasUsed(tx, "createIncreaseOrder gas used");

    const order = await getCreatedIncreaseOrder(user0.address);
    const bnbBalanceAfter = await bnb.balanceOf(orderBook.address);

    const bnbBalanceDiff = bnbBalanceAfter.sub(bnbBalanceBefore);
    expect(bnbBalanceDiff, "BNB balance").to.be.equal(
      amountIn.add(defaults.executionFee)
    );

    validateOrderFields(order, {
      account: defaults.user.address,
      purchaseToken: bnb.address,
      purchaseTokenAmount: amountIn,
      indexToken: btc.address,
      sizeDelta: defaults.sizeDelta,
      isLong: true,
      triggerPrice: defaults.triggerPrice,
      triggerAboveThreshold: true,
      executionFee: defaults.executionFee,
    });
  });

  it("createIncreaseOrder, pay BNB", async () => {
    const bnbBalanceBefore = await bnb.balanceOf(orderBook.address);
    const amountIn = expandDecimals(30, 18);
    const value = defaults.executionFee.add(amountIn);
    const tx = await defaultCreateIncreaseOrder({
      path: [bnb.address],
      amountIn,
      value,
      shouldWrap: true,
    });

    reportGasUsed(tx, "createIncreaseOrder gas used");

    const order = await getCreatedIncreaseOrder(user0.address);
    const bnbBalanceAfter = await bnb.balanceOf(orderBook.address);

    const bnbBalanceDiff = bnbBalanceAfter.sub(bnbBalanceBefore);
    expect(bnbBalanceDiff, "BNB balance").to.be.equal(
      amountIn.add(defaults.executionFee)
    );

    validateOrderFields(order, {
      account: defaults.user.address,
      purchaseToken: bnb.address,
      purchaseTokenAmount: amountIn,
      indexToken: btc.address,
      sizeDelta: defaults.sizeDelta,
      isLong: true,
      triggerPrice: defaults.triggerPrice,
      triggerAboveThreshold: true,
      executionFee: defaults.executionFee,
    });
  });

  it("createIncreaseOrder, long A, transfer and purchase A", async () => {
    const btcBalanceBefore = await btc.balanceOf(orderBook.address);
    const tx = await defaultCreateIncreaseOrder();
    reportGasUsed(tx, "createIncreaseOrder gas used");

    const order = await getCreatedIncreaseOrder(user0.address);
    const btcBalanceAfter = await btc.balanceOf(orderBook.address);

    expect(await bnb.balanceOf(orderBook.address), "BNB balance").to.be.equal(
      defaults.executionFee
    );
    expect(btcBalanceAfter.sub(btcBalanceBefore), "BTC balance").to.be.equal(
      defaults.amountIn
    );

    validateOrderFields(order, {
      account: defaults.user.address,
      purchaseToken: btc.address,
      purchaseTokenAmount: defaults.amountIn,
      indexToken: btc.address,
      sizeDelta: defaults.sizeDelta,
      isLong: true,
      triggerPrice: defaults.triggerPrice,
      triggerAboveThreshold: true,
      executionFee: defaults.executionFee,
    });
  });

  it("createIncreaseOrder, long A, transfer A, purchase B", async () => {
    const daiBalanceBefore = await dai.balanceOf(orderBook.address);
    const tx = await defaultCreateIncreaseOrder({
      path: [btc.address, dai.address],
    });
    reportGasUsed(tx, "createIncreaseOrder gas used");
    const daiBalanceAfter = await dai.balanceOf(orderBook.address);
    const order = await getCreatedIncreaseOrder(defaults.user.address);

    expect(await bnb.balanceOf(orderBook.address), "BNB balance").to.be.equal(
      defaults.executionFee
    );
    expect(daiBalanceAfter, "daiBalanceAfter").to.be.equal(
      daiBalanceBefore.add("59820000000000000000000")
    );

    validateOrderFields(order, {
      account: defaults.user.address,
      purchaseToken: dai.address,
      indexToken: btc.address,
      sizeDelta: defaults.sizeDelta,
      isLong: true,
      triggerPrice: defaults.triggerPrice,
      triggerAboveThreshold: true,
      executionFee: defaults.executionFee,
      purchaseTokenAmount: "59820000000000000000000",
    });
  });

  it("createIncreaseOrder, short A, transfer B, purchase B", async () => {
    const daiBalanceBefore = await dai.balanceOf(orderBook.address);
    const amountIn = expandDecimals(30000, 18);
    const tx = await defaultCreateIncreaseOrder({
      path: [dai.address],
      amountIn,
      isLong: false,
      triggerAboveThreshold: true,
    });
    reportGasUsed(tx, "createIncreaseOrder gas used");
    const daiBalanceAfter = await dai.balanceOf(orderBook.address);

    const order = await getCreatedIncreaseOrder(defaults.user.address);
    expect(await bnb.balanceOf(orderBook.address)).to.be.equal(
      defaults.executionFee
    );
    expect(
      daiBalanceAfter.sub(daiBalanceBefore),
      "daiBalanceAfter"
    ).to.be.equal(amountIn);

    validateOrderFields(order, {
      account: defaults.user.address,
      purchaseToken: dai.address,
      indexToken: btc.address,
      sizeDelta: defaults.sizeDelta,
      isLong: false,
      triggerPrice: defaults.triggerPrice,
      triggerAboveThreshold: true,
      executionFee: defaults.executionFee,
    });
  });

  it("createIncreaseOrder, short A, transfer A, purchase B", async () => {
    const daiBalanceBefore = await dai.balanceOf(orderBook.address);
    const tx = await defaultCreateIncreaseOrder({
      path: [btc.address, dai.address],
      isLong: false,
      triggerAboveThreshold: true,
    });
    reportGasUsed(tx, "createIncreaseOrder gas used");
    const daiBalanceAfter = await dai.balanceOf(orderBook.address);

    const order = await getCreatedIncreaseOrder(defaults.user.address);

    expect(await bnb.balanceOf(orderBook.address)).to.be.equal(
      defaults.executionFee
    );
    expect(daiBalanceAfter).to.be.equal(
      daiBalanceBefore.add("59820000000000000000000")
    );

    validateOrderFields(order, {
      account: defaults.user.address,
      purchaseToken: dai.address,
      indexToken: btc.address,
      sizeDelta: defaults.sizeDelta,
      isLong: false,
      triggerPrice: defaults.triggerPrice,
      triggerAboveThreshold: true,
      executionFee: defaults.executionFee,
    });
    expect(order.purchaseTokenAmount).to.be.equal("59820000000000000000000");
  });

  it("updateIncreaseOrder", async () => {
    await defaultCreateIncreaseOrder();

    const newSizeDelta = defaults.sizeDelta.add(100);
    const newTriggerPrice = defaults.triggerPrice.add(100);
    const newTriggerAboveThreshold = !defaults.triggerAboveThreshold;

    await expect(
      orderBook
        .connect(user1)
        .updateIncreaseOrder(
          0,
          newSizeDelta,
          newTriggerPrice,
          newTriggerAboveThreshold
        )
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    const tx = await orderBook
      .connect(user0)
      .updateIncreaseOrder(
        0,
        newSizeDelta,
        newTriggerPrice,
        newTriggerAboveThreshold
      );
    reportGasUsed(tx, "updateIncreaseOrder gas used");

    let order = await getCreatedIncreaseOrder(user0.address);

    validateOrderFields(order, {
      sizeDelta: newSizeDelta,
      triggerPrice: newTriggerPrice,
      triggerAboveThreshold: newTriggerAboveThreshold,
    });
  });

  it("cancelOrder", async () => {
    const bnbBalanceBefore = await defaults.user.getBalance();
    const tokenBalanceBefore = await btc.balanceOf(defaults.user.address);
    const tx1 = await defaultCreateIncreaseOrder();
    let txFees = await getTxFees(tx1);

    await expect(
      orderBook.connect(user1).cancelIncreaseOrder(0)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    const tx2 = await orderBook.connect(user0).cancelIncreaseOrder(0);
    reportGasUsed(tx2, "cancelIncreaseOrder gas used");

    txFees = txFees.add(await getTxFees(tx2));
    const bnbBalanceAfter = await defaults.user.getBalance();
    expect(bnbBalanceAfter, "bnbBalanceAfter").to.be.equal(
      bnbBalanceBefore.sub(txFees)
    );

    const tokenBalanceAfter = await btc.balanceOf(defaults.user.address);
    expect(tokenBalanceAfter, "tokenBalanceAfter").to.be.equal(
      tokenBalanceBefore
    );

    const order = await getCreatedIncreaseOrder(defaults.user.address);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("cancelOrder, pay BNB", async () => {
    const balanceBefore = await defaults.user.getBalance();
    const bnbBalanceBefore = await bnb.balanceOf(orderBook.address);
    const amountIn = expandDecimals(30, 18);
    const value = defaults.executionFee.add(amountIn);
    const tx1 = await defaultCreateIncreaseOrder({
      path: [bnb.address],
      amountIn,
      value,
      shouldWrap: true,
    });
    let txFees = await getTxFees(tx1);

    await expect(
      orderBook.connect(user1).cancelIncreaseOrder(0)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");

    const tx2 = await orderBook.connect(user0).cancelIncreaseOrder(0);
    reportGasUsed(tx2, "cancelIncreaseOrder gas used");
    txFees = txFees.add(await getTxFees(tx2));

    const balanceAfter = await defaults.user.getBalance();
    expect(balanceAfter, "balanceAfter").to.be.equal(balanceBefore.sub(txFees));

    const order = await getCreatedIncreaseOrder(defaults.user.address);
    expect(order.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeOrder, non-existent order", async () => {
    await expect(
      orderBook.executeIncreaseOrder(user3.address, 0, user1.address)
    ).to.be.revertedWithCustomError(orderBook, "NonexistentOrder");
  });

  it("executeOrder, current price is invalid", async () => {
    let triggerPrice,
      isLong,
      collateralToken,
      triggerAboveThreshold,
      newBtcPrice,
      setPriceTwice;
    let orderIndex = 0;

    // increase long should use max price
    // increase short should use min price
    for ([
      triggerPrice,
      isLong,
      collateralToken,
      triggerAboveThreshold,
      newBtcPrice,
      setPriceTwice,
    ] of [
      [
        expandDecimals(BTC_PRICE - 1000, 30),
        true,
        btc.address,
        false,
        BTC_PRICE - 1050,
        true,
      ],
      [
        expandDecimals(BTC_PRICE + 1000, 30),
        true,
        btc.address,
        true,
        BTC_PRICE + 1050,
        false,
      ],
      [
        expandDecimals(BTC_PRICE - 1000, 30),
        false,
        dai.address,
        false,
        BTC_PRICE - 1050,
        false,
      ],
      [
        expandDecimals(BTC_PRICE + 1000, 30),
        false,
        dai.address,
        true,
        BTC_PRICE + 1050,
        true,
      ],
    ]) {
      await vaultPriceFeed.setPriceSampleSpace(2);

      // "reset" BTC price
      await btcPriceFeed.setLatestAnswer(toChainlinkPrice(BTC_PRICE));
      await btcPriceFeed.setLatestAnswer(toChainlinkPrice(BTC_PRICE));

      await defaultCreateIncreaseOrder({
        triggerPrice,
        isLong,
        triggerAboveThreshold,
        collateralToken,
      });
      const order = await orderBook.increaseOrders(
        defaults.user.address,
        orderIndex
      );
      await expect(
        orderBook.executeIncreaseOrder(order.account, orderIndex, user1.address)
      ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");

      if (setPriceTwice) {
        // in this case on first price order is still non-executable because of current price
        btcPriceFeed.setLatestAnswer(toChainlinkPrice(newBtcPrice));
        await expect(
          orderBook.executeIncreaseOrder(
            order.account,
            orderIndex,
            user1.address
          )
        ).to.be.revertedWithCustomError(orderBook, "InvalidPrice");
      }

      // now both min and max prices satisfies requirement
      btcPriceFeed.setLatestAnswer(toChainlinkPrice(newBtcPrice));
      await orderBook.executeIncreaseOrder(
        order.account,
        orderIndex,
        user1.address
      );

      orderIndex++;
    }
  });

  it("executeOrder, long, purchase token same as collateral", async () => {
    await defaultCreateIncreaseOrder();

    const order = await orderBook.increaseOrders(defaults.user.address, 0);

    const executorBalanceBefore = await user1.getBalance();
    const tx = await orderBook.executeIncreaseOrder(
      defaults.user.address,
      0,
      user1.address
    );
    reportGasUsed(tx, "executeIncreaseOrder gas used");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter).to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const position = positionWrapper(
      await vault.getPosition(
        defaults.user.address,
        btc.address,
        btc.address,
        defaults.isLong
      )
    );
    expect(position.collateral).to.be.equal(
      "59900000000000000000000000000000000"
    );
    expect(position.size).to.be.equal(order.sizeDelta);

    const orderAfter = await orderBook.increaseOrders(defaults.user.address, 0);
    expect(orderAfter.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executOrder, 2 orders with the same position", async () => {
    await defaultCreateIncreaseOrder();

    await orderBook.executeIncreaseOrder(
      defaults.user.address,
      0,
      user1.address
    );
    let position = positionWrapper(
      await vault.getPosition(
        defaults.user.address,
        btc.address,
        btc.address,
        defaults.isLong
      )
    );
    expect(position.collateral).to.be.equal(
      "59900000000000000000000000000000000"
    );
    expect(position.size).to.be.equal(defaults.sizeDelta);

    await defaultCreateIncreaseOrder();

    await orderBook.executeIncreaseOrder(
      defaults.user.address,
      1,
      user1.address
    );
    position = positionWrapper(
      await vault.getPosition(
        defaults.user.address,
        btc.address,
        btc.address,
        defaults.isLong
      )
    );
    expect(position.collateral).to.be.equal(
      "119800000000000000000000000000000000"
    );
    expect(position.size).to.be.equal(defaults.sizeDelta.mul(2));
  });

  it("executeOrder, long, swap purchase token to collateral", async () => {
    await defaultCreateIncreaseOrder({
      path: [dai.address],
      amountIn: expandDecimals(50000, 18),
    });

    const executorBalanceBefore = await user1.getBalance();
    const order = await orderBook.increaseOrders(defaults.user.address, 0);
    const tx = await orderBook.executeIncreaseOrder(
      defaults.user.address,
      0,
      user1.address
    );
    reportGasUsed(tx, "executeIncreaseOrder gas used");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter).to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const position = positionWrapper(
      await vault.getPosition(
        user0.address,
        btc.address,
        btc.address,
        defaults.isLong
      )
    );
    expect(position.size, "size").to.be.equal(order.sizeDelta);
    expect(position.collateral, "collateral").to.be.equal(
      "49749999800000000000000000000000000"
    );

    const orderAfter = await orderBook.increaseOrders(defaults.user.address, 0);
    expect(orderAfter.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeOrder, short, purchase token same as collateral", async () => {
    dai.mint(user0.address, expandDecimals(50000, 18));
    await defaultCreateIncreaseOrder({
      path: [dai.address],
      collateralToken: dai.address,
      isLong: false,
      amountIn: expandDecimals(50000, 18),
      triggerAboveThreshold: true,
      triggerPrice: expandDecimals(BTC_PRICE - 100, 30),
    });

    const executorBalanceBefore = await user1.getBalance();

    const order = await orderBook.increaseOrders(defaults.user.address, 0);
    const tx = await orderBook.executeIncreaseOrder(
      defaults.user.address,
      0,
      user1.address
    );
    reportGasUsed(tx, "executeIncreaseOrder gas used");

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter).to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const position = positionWrapper(
      await vault.getPosition(
        defaults.user.address,
        dai.address,
        btc.address,
        false
      )
    );
    expect(position.collateral).to.be.equal(
      "49900000000000000000000000000000000"
    );
    expect(position.size, "position.size").to.be.equal(order.sizeDelta);

    const orderAfter = await orderBook.increaseOrders(defaults.user.address, 0);
    expect(orderAfter.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeOrder, short, swap purchase token to collateral", async () => {
    await defaultCreateIncreaseOrder({
      isLong: false,
      collateralToken: dai.address,
      triggerAboveThreshold: true,
      triggerPrice: expandDecimals(BTC_PRICE - 100, 30),
    });

    const executorBalanceBefore = await user1.getBalance();

    const order = await orderBook.increaseOrders(defaults.user.address, 0);
    const tx = await orderBook.executeIncreaseOrder(
      defaults.user.address,
      0,
      user1.address
    );
    reportGasUsed(tx, "executeIncreaseOrder gas used");

    const position = positionWrapper(
      await vault.getPosition(user0.address, dai.address, btc.address, false)
    );
    expect(position.collateral).to.be.equal(
      "59720000000000000000000000000000000"
    );
    expect(position.size, "position.size").to.be.equal(order.sizeDelta);

    const executorBalanceAfter = await user1.getBalance();
    expect(executorBalanceAfter).to.be.equal(
      executorBalanceBefore.add(defaults.executionFee)
    );

    const orderAfter = await orderBook.increaseOrders(defaults.user.address, 0);
    expect(orderAfter.account).to.be.equal(ZERO_ADDRESS);
  });

  it("executeOrder, short, pay BNB, no swap", async () => {
    const amountIn = expandDecimals(50, 18);
    const value = defaults.executionFee.add(amountIn);
    await defaultCreateIncreaseOrder({
      path: [bnb.address],
      amountIn,
      value,
      indexToken: bnb.address,
      collateralToken: dai.address,
      isLong: false,
      triggerboveThreshold: true,
      triggerPrice: expandDecimals(BNB_PRICE - 10, 30),
      shouldWrap: true,
    });

    const order = await orderBook.increaseOrders(defaults.user.address, 0);
    const tx = await orderBook.executeIncreaseOrder(
      defaults.user.address,
      0,
      user1.address
    );
    reportGasUsed(tx, "executeIncreaseOrder gas used");

    const position = positionWrapper(
      await vault.getPosition(user0.address, dai.address, bnb.address, false)
    );
    expect(position.collateral).to.be.equal(
      "14855000000000000000000000000000000"
    );
    expect(position.size, "position.size").to.be.equal(order.sizeDelta);

    const orderAfter = await orderBook.increaseOrders(defaults.user.address, 0);
    expect(orderAfter.account).to.be.equal(ZERO_ADDRESS);
  });

  it("createIncreaseOrder, bad path", async () => {
    await expect(
      defaultCreateIncreaseOrder({
        path: [btc.address, btc.address],
      })
    ).to.be.revertedWithCustomError(orderBook, "InvalidPath");
  });
});
