import { toUsd } from "../../shared/units";
import { deployContract } from "../../shared/fixtures";

export async function initVaultUtils(vault: any) {
  const vaultUtils = await deployContract("VaultUtils", [vault.address]);
  await vault.setVaultUtils(vaultUtils.address);
  return vaultUtils;
}

export async function initVault(
  vault: any,
  router: any,
  usdv: any,
  priceFeed: any
) {
  await vault.initialize(
    router.address, // router
    usdv.address, // usdv
    priceFeed.address, // priceFeed
    toUsd(5), // liquidationFeeUsd
    600, // fundingRateFactor
    600 // stableFundingRateFactor
  );

  const vaultUtils = await initVaultUtils(vault);

  return { vault, vaultUtils };
}

export async function validateVaultBalance(
  expect: any,
  vault: any,
  token: any,
  offset: any = 0
) {
  const poolAmount = await vault.poolAmounts(token.address);
  const feeReserve = await vault.feeReserves(token.address);
  const balance = await token.balanceOf(vault.address);
  let amount = poolAmount.add(feeReserve);
  expect(balance).gt(0);
  expect(poolAmount.add(feeReserve).add(offset)).eq(balance);
}

export function getBnbConfig(bnb: any, bnbPriceFeed: any) {
  return [
    bnb.address, // _token
    18, // _tokenDecimals
    10000, // _tokenWeight
    75, // _minProfitBps,
    0, // _maxUsdvAmount
    false, // _isStable
    true, // _isShortable
  ];
}

export function getEthConfig(eth: any, ethPriceFeed: any) {
  return [
    eth.address, // _token
    18, // _tokenDecimals
    10000, // _tokenWeight
    75, // _minProfitBps
    0, // _maxUsdvAmount
    false, // _isStable
    true, // _isShortable
  ];
}

export function getBtcConfig(btc: any, btcPriceFeed: any) {
  return [
    btc.address, // _token
    8, // _tokenDecimals
    10000, // _tokenWeight
    75, // _minProfitBps
    0, // _maxUsdvAmount
    false, // _isStable
    true, // _isShortable
  ];
}

export function getDaiConfig(dai: any, daiPriceFeed: any) {
  return [
    dai.address, // _token
    18, // _tokenDecimals
    10000, // _tokenWeight
    75, // _minProfitBps
    0, // _maxUsdvAmount
    true, // _isStable
    false, // _isShortable
  ];
}
