import { expect } from "chai";
import { ethers } from "hardhat";
import { expandDecimals } from "../../shared/utilities";

export const PRICE_PRECISION = ethers.BigNumber.from(10).pow(30);
export const BASIS_POINTS_DIVISOR = 10000;

export function getDefault(obj: any, name: any, defaultValue: any) {
  return name in obj ? obj[name] : defaultValue;
}

export function validateOrderFields(order: any, fields: Object) {
  for (const [key, value] of Object.entries(fields)) {
    if (key === "path") {
      order.path.forEach((item: any, index: any) => {
        expect(item, key).to.be.equal(value[index]);
      });
      return;
    }
    if (value === true) return expect(order[key], key).to.be.true;
    if (value === false) return expect(order[key], key).to.be.false;
    expect(order[key], key).to.be.equal(value);
  }
}

export function getTriggerRatio(tokenAUsd: any, tokenBUsd: any) {
  return tokenBUsd.mul(PRICE_PRECISION).div(tokenAUsd);
}

export async function getTxFees(tx: any) {
  const receipt = await ethers.provider.getTransactionReceipt(tx.hash);
  // use receipt.effectiveGasPrice for newer versions of hardhat
  return receipt.effectiveGasPrice.mul(receipt.gasUsed);
}

export function positionWrapper(position: any) {
  return {
    size: position[0],
    collateral: position[1],
    averagePrice: position[2],
    entryFundingRate: position[3],
    reserveAmount: position[4],
  };
}

export function defaultCreateIncreaseOrderFactory(
  orderBook: any,
  defaults: any
) {
  return function defaultCreateIncreaseOrder(props: any = {}) {
    return orderBook
      .connect(getDefault(props, "user", defaults.user))
      .createIncreaseOrder(
        getDefault(props, "path", defaults.path),
        getDefault(props, "amountIn", defaults.amountIn),
        getDefault(
          props,
          "indexToken",
          defaults.path[defaults.path.length - 1]
        ),
        getDefault(props, "minOut", defaults.minOut),
        getDefault(props, "sizeDelta", defaults.sizeDelta),
        getDefault(props, "collateralToken", defaults.collateralToken), // _collateralToken
        getDefault(props, "isLong", defaults.isLong),
        getDefault(props, "triggerPrice", defaults.triggerPrice),
        getDefault(
          props,
          "triggerAboveThreshold",
          defaults.triggerAboveThreshold
        ),
        getDefault(props, "executionFee", defaults.executionFee),
        getDefault(props, "shouldWrap", defaults.shouldWrap),
        {
          value: getDefault(
            props,
            "value",
            props.executionFee || defaults.executionFee
          ),
        }
      );
  };
}

export function defaultCreateDecreaseOrderFactory(
  orderBook: any,
  defaults: any
) {
  return function defaultCreateDecreaseOrder(props: any = {}) {
    return orderBook
      .connect(getDefault(props, "user", defaults.user))
      .createDecreaseOrder(
        getDefault(
          props,
          "indexToken",
          defaults.path[defaults.path.length - 1]
        ),
        getDefault(props, "sizeDelta", defaults.sizeDelta),
        getDefault(props, "collateralToken", defaults.collateralToken),
        getDefault(props, "collateralDelta", defaults.collateralDelta),
        getDefault(props, "isLong", defaults.isLong),
        getDefault(props, "triggerPrice", defaults.triggerPrice),
        getDefault(
          props,
          "triggerAboveThreshold",
          defaults.triggerAboveThreshold
        ),
        {
          value: getDefault(
            props,
            "value",
            props.executionFee || defaults.executionFee
          ),
        }
      );
  };
}

export function defaultCreateSwapOrderFactory(
  orderBook: any,
  defaults: any,
  tokenDecimals: any
) {
  return async function defaultCreateSwapOrder(props: any = {}) {
    if (!("triggerRatio" in props) && !("minOut" in props)) {
      throw new Error("Either triggerRatio or minOut should be provided");
    }

    props.triggerRatio = props.triggerRatio || 0;
    props.amountIn = getDefault(props, "amountIn", defaults.amountIn);
    props.path = getDefault(props, "path", defaults.path);
    props.minOut =
      props.minOut ||
      (await getMinOut(
        tokenDecimals,
        props.triggerRatio,
        props.path,
        props.amountIn
      ));
    props.triggerAboveThreshold = getDefault(
      props,
      "triggerAboveThreshold",
      defaults.triggerAboveThreshold
    );
    props.executionFee = getDefault(
      props,
      "executionFee",
      defaults.executionFee
    );
    props.value = getDefault(
      props,
      "value",
      props.executionFee || defaults.executionFee
    );
    props.shouldWrap = getDefault(props, "shouldWrap", defaults.shouldWrap);
    props.shouldUnwrap = getDefault(
      props,
      "shouldUnwrap",
      defaults.shouldUnwrap
    );

    const account = getDefault(props, "user", defaults.user);
    const tx = await orderBook
      .connect(account)
      .createSwapOrder(
        props.path,
        props.amountIn,
        props.minOut,
        props.triggerRatio,
        props.triggerAboveThreshold,
        props.executionFee,
        props.shouldWrap,
        props.shouldUnwrap,
        { value: props.value }
      );

    return [tx, props];
  };
}

export function getSwapFees(token: any, amount: any) {
  // ideally to get all this from Vault in runtime
  //
  let feesPoints;
  //   if ([dai.address, busd.address, usdv.address].includes(token)) {
  //     feesPoints = 4;
  //   } else {
  //     feesPoints = 30;
  //   }
  feesPoints = 30;
  return amount.mul(feesPoints).div(BASIS_POINTS_DIVISOR);
}

export async function getMinOut(
  tokenDecimals: any,
  triggerRatio: any,
  path: any,
  amountIn: any
) {
  const tokenAPrecision = expandDecimals(1, tokenDecimals[path[0]]);
  const tokenBPrecision = expandDecimals(
    1,
    tokenDecimals[path[path.length - 1]]
  );

  let minOut = amountIn
    .mul(PRICE_PRECISION)
    .div(triggerRatio)
    .mul(tokenBPrecision)
    .div(tokenAPrecision);
  const swapFees = getSwapFees(path[path.length - 1], minOut);
  return minOut.sub(swapFees);
}
