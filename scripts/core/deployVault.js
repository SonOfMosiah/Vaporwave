// import { Vault__factory, Router__factory, VaultPriceFeed__factory } from "../../typechain-types";

// const network = (process.env.HARDHAT_NETWORK || 'mainnet');
// const tokens = require('./tokens')[network];

// async function main() {
//   const { nativeToken } = tokens

//   const Vault = (await ethers.getContractFactory(
//     "Vault"
//   )) as Vault__factory;

//   const vault = await Vault.deploy();

//   // const Router = (await ethers.getContractFactory(
//   //   "Router"
//   // )) as Router__factory;

//   // const router = await Router.deploy(vault.address, usdv, weth);

//   // const VaultPriceFeed = (await ethers.getContractFactory(
//   //   "VaultPriceFeed"
//   // )) as VaultPriceFeed__factory

//   // const vaultPriceFeed = await VaultPriceFeed.deploy()

//   // await sendTxn(vaultPriceFeed.setMaxStrictPriceDeviation(expandDecimals(5, 28)), "vaultPriceFeed.setMaxStrictPriceDeviation") // 0.05 USD
//   // await sendTxn(vaultPriceFeed.setPriceSampleSpace(1), "vaultPriceFeed.setPriceSampleSpace")
//   // await sendTxn(vaultPriceFeed.setIsAmmEnabled(false), "vaultPriceFeed.setIsAmmEnabled")

//   // const glp = await deployContract("GLP", [])
//   // await sendTxn(glp.setInPrivateTransferMode(true), "glp.setInPrivateTransferMode")
//   // // const glp = await contractAt("GLP", "0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258")
//   // const glpManager = await deployContract("GlpManager", [vault.address, usdg.address, glp.address, 15 * 60])
//   // await sendTxn(glpManager.setInPrivateMode(true), "glpManager.setInPrivateMode")

//   // await sendTxn(glp.setMinter(glpManager.address, true), "glp.setMinter")
//   // await sendTxn(usdg.addVault(glpManager.address), "usdg.addVault(glpManager)")

//   // await sendTxn(vault.initialize(
//   //   router.address, // router
//   //   usdg.address, // usdg
//   //   vaultPriceFeed.address, // priceFeed
//   //   toUsd(2), // liquidationFeeUsd
//   //   100, // fundingRateFactor
//   //   100 // stableFundingRateFactor
//   // ), "vault.initialize")

//   // await sendTxn(vault.setFundingRate(60 * 60, 100, 100), "vault.setFundingRate")

//   // await sendTxn(vault.setInManagerMode(true), "vault.setInManagerMode")
//   // await sendTxn(vault.setManager(glpManager.address, true), "vault.setManager")

//   // await sendTxn(vault.setFees(
//   //   10, // _taxBasisPoints
//   //   5, // _stableTaxBasisPoints
//   //   20, // _mintBurnFeeBasisPoints
//   //   20, // _swapFeeBasisPoints
//   //   1, // _stableSwapFeeBasisPoints
//   //   10, // _marginFeeBasisPoints
//   //   toUsd(2), // _liquidationFeeUsd
//   //   24 * 60 * 60, // _minProfitTime
//   //   true // _hasDynamicFees
//   // ), "vault.setFees")

//   // const vaultErrorController = await deployContract("VaultErrorController", [])
//   // await sendTxn(vault.setErrorController(vaultErrorController.address), "vault.setErrorController")
//   // await sendTxn(vaultErrorController.setErrors(vault.address, errors), "vaultErrorController.setErrors")

//   // const vaultUtils = await deployContract("VaultUtils", [vault.address])
//   // await sendTxn(vault.setVaultUtils(vaultUtils.address), "vault.setVaultUtils")
// }

// main()
//   .then(() => process.exit(0))
//   .catch(error => {
//     console.error(error)
//     process.exit(1)
//   })
