import hre, { ethers } from "hardhat";
import { BigNumber } from "ethers";

const maxUint256 = ethers.constants.MaxUint256;

export function newWallet() {
  return ethers.Wallet.createRandom();
}

export function bigNumberify(n: any) {
  return ethers.BigNumber.from(n);
}

export function expandDecimals(n: number, decimals: number) {
  return bigNumberify(n).mul(bigNumberify(10).pow(decimals));
}

export async function send(provider: any, method: any, params = []) {
  await provider.send(method, params);
}

export async function mineBlock(provider: any) {
  await send(provider, "evm_mine");
}

export async function increaseTime(provider: any, seconds: never) {
  await send(provider, "evm_increaseTime", [seconds]);
}

export async function gasUsed(provider: any, tx: any) {
  return (await provider.getTransactionReceipt(tx.hash)).gasUsed;
}

export async function getNetworkFee(provider: any, tx: any) {
  const gas = await gasUsed(provider, tx);
  return gas.mul(tx.gasPrice);
}

export async function reportGasUsed(tx: any, label: any) {
  const { gasUsed } = await ethers.provider.getTransactionReceipt(tx.hash);
  console.info(label, gasUsed.toString());
}

export async function getBlockTime(provider: any) {
  const blockNumber = await provider.getBlockNumber();
  const block = await provider.getBlock(blockNumber);
  return block.timestamp;
}

export async function getTxnBalances(
  provider: any,
  user: any,
  txn: any,
  callback: any
) {
  const balance0 = await provider.getBalance(user.address);
  const tx = await txn();
  const fee = await getNetworkFee(provider, tx);
  const balance1 = await provider.getBalance(user.address);
  callback(balance0, balance1, fee);
}

export function print(label: any, value: any, decimals: any) {
  if (decimals === 0) {
    console.log(label, value.toString());
    return;
  }
  const valueStr = ethers.utils.formatUnits(value, decimals);
  console.log(label, valueStr);
}

export function getPriceBitArray(prices: any) {
  let priceBitArray = [];
  let shouldExit = false;

  for (let i = 0; i < Number((prices.length - 1) / 8) + 1; i++) {
    let priceBits = BigNumber.from("0");
    for (let j = 0; j < 8; j++) {
      let index = i * 8 + j;
      if (index >= prices.length) {
        shouldExit = true;
        break;
      }

      const price = BigNumber.from(prices[index]);
      if (price.gt(BigNumber.from("2147483648"))) {
        // 2^31
        throw new Error(`price exceeds bit limit ${price.toString()}`);
      }
      priceBits = priceBits.or(price.shl(j * 32));
    }

    priceBitArray.push(priceBits.toString());

    if (shouldExit) {
      break;
    }
  }

  return priceBitArray;
}

export function getPriceBits(prices: any) {
  if (prices.length > 8) {
    throw new Error("max prices.length exceeded");
  }

  let priceBits = BigNumber.from("0");

  for (let j = 0; j < 8; j++) {
    let index = j;
    if (index >= prices.length) {
      break;
    }

    const price = BigNumber.from(prices[index]);
    if (price.gt(BigNumber.from("2147483648"))) {
      // 2^31
      throw new Error(`price exceeds bit limit ${price.toString()}`);
    }

    priceBits = priceBits.or(price.shl(j * 32));
  }

  return priceBits.toString();
}
