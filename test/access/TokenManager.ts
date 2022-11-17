import {
  time,
  takeSnapshot,
  mine,
} from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import log from "ololog";

import { deployContract } from "../shared/fixtures";

const { AddressZero } = ethers.constants;

describe("TokenManager", () => {
  const provider = ethers.providers;
  let wallet: any,
    user0: any,
    user1: any,
    user2: any,
    signer0: any,
    signer1: any,
    signer2: any;
  let vwave: any;
  let eth: any;
  let tokenManager: any;
  let timelock: any;
  let vwaveTimelock: any;
  let nft0: any;
  let nft1: any;
  const nftId: number = 17;
  let amount = ethers.utils.parseEther("5");
  let vwaveAddress = "0x2451dB68DeD81900C4F16ae1af597E9658689734";

  before(async () => {
    [wallet, user0, user1, user2, signer0, signer1, signer2] =
      await ethers.getSigners();

    let Eth = await ethers.getContractFactory("Token");
    eth = await Eth.deploy();
  });

  beforeEach(async () => {
    let TokenManager = await ethers.getContractFactory("TokenManager");
    tokenManager = await TokenManager.deploy(2);

    await tokenManager.initialize([
      signer0.address,
      signer1.address,
      signer2.address,
    ]);

    const Vwave = await ethers.getContractFactory("VWAVE");
    vwave = Vwave.attach(vwaveAddress);

    const NFT0 = await ethers.getContractFactory("ERC721");
    nft0 = await NFT0.deploy("NFT0", "NFT0");
    const NFT1 = await ethers.getContractFactory("ERC721");
    nft1 = await NFT1.deploy("NFT1", "NFT1");

    const Timelock = await ethers.getContractFactory("Timelock");
    timelock = await Timelock.deploy(
      wallet.address,
      5 * 24 * 60 * 60,
      user0.address,
      tokenManager.address,
      user2.address,
      ethers.utils.parseEther("1000"),
      10,
      100
    );

    const VwaveTimelock = await ethers.getContractFactory("VwaveTimelock");
    vwaveTimelock = await VwaveTimelock.deploy(
      wallet.address,
      5 * 24 * 60 * 60,
      7 * 24 * 60 * 60,
      user0.address,
      tokenManager.address,
      user2.address,
      ethers.utils.parseEther("1000")
    );
  });

  it("inits", async () => {
    await expect(
      tokenManager.initialize([
        signer0.address,
        signer1.address,
        signer2.address,
      ])
    ).to.be.revertedWithCustomError(tokenManager, "AlreadyInitialized");

    expect(await tokenManager.signers(0)).eq(signer0.address);
    expect(await tokenManager.signers(1)).eq(signer1.address);
    expect(await tokenManager.signers(2)).eq(signer2.address);
    expect(await tokenManager.signersLength()).eq(3);

    expect(await tokenManager.isSigner(user0.address)).eq(false);
    expect(await tokenManager.isSigner(signer0.address)).eq(true);
    expect(await tokenManager.isSigner(signer1.address)).eq(true);
    expect(await tokenManager.isSigner(signer2.address)).eq(true);
  });

  it("signalApprove", async () => {
    await expect(
      tokenManager
        .connect(user0)
        .signalApprove(eth.address, user2.address, amount)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(wallet)
      .signalApprove(eth.address, user2.address, amount);
  });

  it("signApprove", async () => {
    await expect(
      tokenManager
        .connect(user0)
        .signApprove(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(signer2)
        .signApprove(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(wallet)
      .signalApprove(eth.address, user2.address, amount);

    await expect(
      tokenManager
        .connect(user0)
        .signApprove(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(signer2)
      .signApprove(eth.address, user2.address, amount, 1);

    await expect(
      tokenManager
        .connect(signer2)
        .signApprove(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "AlreadySigned");

    await tokenManager
      .connect(signer1)
      .signApprove(eth.address, user2.address, amount, 1);
  });

  it("approve", async () => {
    await eth.mint(tokenManager.address, amount);

    await expect(
      tokenManager.connect(user0).approve(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(wallet)
        .approve(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(wallet)
      .signalApprove(eth.address, user2.address, amount);

    await expect(
      tokenManager
        .connect(wallet)
        .approve(vwave.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approve(eth.address, user0.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approve(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer0)
      .signApprove(eth.address, user2.address, amount, 1);

    await expect(
      tokenManager
        .connect(wallet)
        .approve(eth.address, user2.address, amount, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer2)
      .signApprove(eth.address, user2.address, amount, 1);

    await expect(
      eth
        .connect(user2)
        .transferFrom(
          tokenManager.address,
          user1.address,
          ethers.utils.parseEther("4")
        )
    ).to.be.revertedWithCustomError(eth, "InsufficientAllowance");

    await tokenManager
      .connect(wallet)
      .approve(eth.address, user2.address, amount, 1);

    await expect(
      eth
        .connect(user2)
        .transferFrom(
          tokenManager.address,
          user1.address,
          ethers.utils.parseEther("6")
        )
    ).to.be.revertedWithCustomError(eth, "InsufficientBalance");

    expect(await eth.balanceOf(user1.address)).eq(0);
    await eth
      .connect(user2)
      .transferFrom(tokenManager.address, user1.address, amount);
    expect(await eth.balanceOf(user1.address)).eq(amount);
  });

  it("signalApproveNFT", async () => {
    await expect(
      tokenManager
        .connect(user0)
        .signalApproveNFT(eth.address, user2.address, nftId)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(wallet)
      .signalApproveNFT(eth.address, user2.address, nftId);
  });

  it("signApproveNFT", async () => {
    await expect(
      tokenManager
        .connect(user0)
        .signApproveNFT(eth.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(signer2)
        .signApproveNFT(eth.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(wallet)
      .signalApproveNFT(eth.address, user2.address, nftId);

    await expect(
      tokenManager
        .connect(user0)
        .signApproveNFT(eth.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(signer2)
      .signApproveNFT(eth.address, user2.address, nftId, 1);

    await expect(
      tokenManager
        .connect(signer2)
        .signApproveNFT(eth.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "AlreadySigned");

    await tokenManager
      .connect(signer1)
      .signApproveNFT(eth.address, user2.address, nftId, 1);
  });

  it("approveNFT", async () => {
    await nft0.mint(tokenManager.address, nftId);
    await nft1.mint(tokenManager.address, nftId);

    await expect(
      tokenManager
        .connect(user0)
        .approveNFT(nft0.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFT(nft0.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(wallet)
      .signalApproveNFT(nft0.address, user2.address, nftId);

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFT(nft1.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFT(nft0.address, user0.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFT(nft0.address, user2.address, nftId + 1, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFT(nft0.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer0)
      .signApproveNFT(nft0.address, user2.address, nftId, 1);

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFT(nft0.address, user2.address, nftId, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer2)
      .signApproveNFT(nft0.address, user2.address, nftId, 1);

    await expect(
      nft0
        .connect(user2)
        .transferFrom(tokenManager.address, user1.address, nftId)
    ).to.be.revertedWith("ERC721: caller is not token owner or approved");

    await tokenManager
      .connect(wallet)
      .approveNFT(nft0.address, user2.address, nftId, 1);

    expect(await nft0.balanceOf(user1.address)).eq(0);
    expect(await nft0.balanceOf(tokenManager.address)).eq(1);
    expect(await nft0.ownerOf(nftId)).eq(tokenManager.address);

    await nft0
      .connect(user2)
      .transferFrom(tokenManager.address, user1.address, nftId);

    expect(await nft0.balanceOf(user1.address)).eq(1);
    expect(await nft0.balanceOf(tokenManager.address)).eq(0);
    expect(await nft0.ownerOf(nftId)).eq(user1.address);

    await expect(
      nft0
        .connect(user2)
        .transferFrom(tokenManager.address, user1.address, nftId)
    ).to.be.revertedWith("ERC721: caller is not token owner or approved");
  });

  it("signalApproveNFTs", async () => {
    const nftId0 = 21;
    const nftId1 = 22;

    await expect(
      tokenManager
        .connect(user0)
        .signalApproveNFTs(nft0.address, user2.address, [nftId0, nftId1])
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(wallet)
      .signalApproveNFTs(nft0.address, user2.address, [nftId0, nftId1]);
  });

  it("signApproveNFTs", async () => {
    const nftId0 = 21;
    const nftId1 = 22;

    await expect(
      tokenManager
        .connect(user0)
        .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(signer2)
        .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(wallet)
      .signalApproveNFTs(nft0.address, user2.address, [nftId0, nftId1]);

    await expect(
      tokenManager
        .connect(user0)
        .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(signer2)
      .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1);

    await expect(
      tokenManager
        .connect(signer2)
        .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "AlreadySigned");

    await tokenManager
      .connect(signer1)
      .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1);
  });

  it("approveNFTs", async () => {
    const nftId0 = 21;
    const nftId1 = 22;

    await nft0.mint(tokenManager.address, nftId0);
    await nft0.mint(tokenManager.address, nftId1);

    await expect(
      tokenManager
        .connect(user0)
        .approveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(wallet)
      .signalApproveNFTs(nft0.address, user2.address, [nftId0, nftId1]);

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFTs(nft1.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFTs(nft0.address, user0.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFTs(nft0.address, user2.address, [nftId0, nftId1 + 1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer0)
      .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1);

    await expect(
      tokenManager
        .connect(wallet)
        .approveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer2)
      .signApproveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1);

    await expect(
      nft0
        .connect(user2)
        .transferFrom(tokenManager.address, user1.address, nftId0)
    ).to.be.revertedWith("ERC721: caller is not token owner or approved");

    await tokenManager
      .connect(wallet)
      .approveNFTs(nft0.address, user2.address, [nftId0, nftId1], 1);

    expect(await nft0.balanceOf(user1.address)).eq(0);
    expect(await nft0.balanceOf(tokenManager.address)).eq(2);
    expect(await nft0.ownerOf(nftId0)).eq(tokenManager.address);
    expect(await nft0.ownerOf(nftId1)).eq(tokenManager.address);

    await nft0
      .connect(user2)
      .transferFrom(tokenManager.address, user1.address, nftId0);

    expect(await nft0.balanceOf(user1.address)).eq(1);
    expect(await nft0.balanceOf(tokenManager.address)).eq(1);
    expect(await nft0.ownerOf(nftId0)).eq(user1.address);
    expect(await nft0.ownerOf(nftId1)).eq(tokenManager.address);

    await nft0
      .connect(user2)
      .transferFrom(tokenManager.address, user1.address, nftId1);

    expect(await nft0.balanceOf(user1.address)).eq(2);
    expect(await nft0.balanceOf(tokenManager.address)).eq(0);
    expect(await nft0.ownerOf(nftId0)).eq(user1.address);
    expect(await nft0.ownerOf(nftId1)).eq(user1.address);
  });

  it("receiveNFTs", async () => {
    const nftId0 = 21;
    const nftId1 = 22;

    await nft0.mint(tokenManager.address, nftId0);
    await nft0.mint(tokenManager.address, nftId1);

    const TokenManager2 = await ethers.getContractFactory("TokenManager");
    const tokenManager2 = await TokenManager2.deploy(2);
    await tokenManager2.initialize([
      signer0.address,
      signer1.address,
      signer2.address,
    ]);

    await tokenManager
      .connect(wallet)
      .signalApproveNFTs(nft0.address, tokenManager2.address, [nftId0, nftId1]);
    await tokenManager
      .connect(signer0)
      .signApproveNFTs(
        nft0.address,
        tokenManager2.address,
        [nftId0, nftId1],
        1
      );
    await tokenManager
      .connect(signer2)
      .signApproveNFTs(
        nft0.address,
        tokenManager2.address,
        [nftId0, nftId1],
        1
      );

    await expect(
      tokenManager2.receiveNFTs(nft0.address, tokenManager.address, [
        nftId0,
        nftId1,
      ])
    ).to.be.revertedWith("ERC721: caller is not token owner or approved");

    await tokenManager
      .connect(wallet)
      .approveNFTs(nft0.address, tokenManager2.address, [nftId0, nftId1], 1);

    expect(await nft0.balanceOf(tokenManager.address)).eq(2);
    expect(await nft0.balanceOf(tokenManager2.address)).eq(0);
    expect(await nft0.ownerOf(nftId0)).eq(tokenManager.address);
    expect(await nft0.ownerOf(nftId1)).eq(tokenManager.address);

    await tokenManager2.receiveNFTs(nft0.address, tokenManager.address, [
      nftId0,
      nftId1,
    ]);

    expect(await nft0.balanceOf(tokenManager.address)).eq(0);
    expect(await nft0.balanceOf(tokenManager2.address)).eq(2);
    expect(await nft0.ownerOf(nftId0)).eq(tokenManager2.address);
    expect(await nft0.ownerOf(nftId1)).eq(tokenManager2.address);
  });

  it("signalSetAdmin", async () => {
    await expect(
      tokenManager
        .connect(user0)
        .signalSetAdmin(timelock.address, user1.address)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(wallet)
        .signalSetAdmin(timelock.address, user1.address)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await tokenManager
      .connect(signer0)
      .signalSetAdmin(timelock.address, user1.address);
  });

  it("signSetAdmin", async () => {
    await expect(
      tokenManager
        .connect(user0)
        .signSetAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(wallet)
        .signSetAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(signer1)
        .signSetAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(signer1)
      .signalSetAdmin(timelock.address, user1.address);

    await expect(
      tokenManager
        .connect(user0)
        .signSetAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager
        .connect(signer1)
        .signSetAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "AlreadySigned");

    await tokenManager
      .connect(signer2)
      .signSetAdmin(timelock.address, user1.address, 1);

    await expect(
      tokenManager
        .connect(signer2)
        .signSetAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "AlreadySigned");
  });

  it("setAdmin", async () => {
    await expect(
      tokenManager.connect(user0).setAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager.connect(wallet).setAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

    await expect(
      tokenManager.connect(signer0).setAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await tokenManager
      .connect(signer0)
      .signalSetAdmin(timelock.address, user1.address);

    await expect(
      tokenManager.connect(signer0).setAdmin(user0.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager.connect(signer0).setAdmin(timelock.address, user0.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager.connect(signer0).setAdmin(timelock.address, user1.address, 2)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

    await expect(
      tokenManager.connect(signer0).setAdmin(timelock.address, user1.address, 1)
    ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

    await tokenManager
      .connect(signer2)
      .signSetAdmin(timelock.address, user1.address, 1);

    expect(await timelock.admin()).eq(wallet.address);
    await tokenManager
      .connect(signer2)
      .setAdmin(timelock.address, user1.address, 1);
    expect(await timelock.admin()).eq(user1.address);
  });

  // NOTE: VWAVE does not have a setGov function

  // it("signalSetGov", async () => {
  //   await expect(
  //     tokenManager
  //       .connect(user0)
  //       .signalSetGov(timelock.address, vwave.address, user1.address)
  //   ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

  //   await tokenManager
  //     .connect(wallet)
  //     .signalSetGov(timelock.address, vwave.address, user1.address);
  // });

  // it("signSetGov", async () => {
  //   await expect(
  //     tokenManager
  //       .connect(user0)
  //       .signSetGov(timelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

  //   await expect(
  //     tokenManager
  //       .connect(signer2)
  //       .signSetGov(timelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

  //   await tokenManager
  //     .connect(wallet)
  //     .signalSetGov(timelock.address, vwave.address, user1.address);

  //   await expect(
  //     tokenManager
  //       .connect(user0)
  //       .signSetGov(timelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

  //   await tokenManager
  //     .connect(signer2)
  //     .signSetGov(timelock.address, vwave.address, user1.address, 1);

  //   await expect(
  //     tokenManager
  //       .connect(signer2)
  //       .signSetGov(timelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "AlreadySigned");

  //   await tokenManager
  //     .connect(signer1)
  //     .signSetGov(timelock.address, vwave.address, user1.address, 1);
  // });

  // it("setGov", async () => {
  //   await vwave.setGov(vwaveTimelock.address);

  //   await expect(
  //     tokenManager
  //       .connect(user0)
  //       .setGov(vwaveTimelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "Forbidden");

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(vwaveTimelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

  //   await tokenManager
  //     .connect(wallet)
  //     .signalSetGov(vwaveTimelock.address, vwave.address, user1.address);

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(user2.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(vwaveTimelock.address, user0.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(vwaveTimelock.address, vwave.address, user2.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(vwaveTimelock.address, vwave.address, user1.address, 1 + 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotSignalled");

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(vwaveTimelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

  //   await tokenManager
  //     .connect(signer0)
  //     .signSetGov(vwaveTimelock.address, vwave.address, user1.address, 1);

  //   await expect(
  //     tokenManager
  //       .connect(wallet)
  //       .setGov(vwaveTimelock.address, vwave.address, user1.address, 1)
  //   ).to.be.revertedWithCustomError(tokenManager, "ActionNotAuthorized");

  //   await expect(
  //     vwaveTimelock.connect(wallet).signalSetGov(vwave.address, user1.address)
  //   ).to.be.revertedWith("GmxTimelock: forbidden");

  //   await tokenManager
  //     .connect(signer2)
  //     .signSetGov(vwaveTimelock.address, vwave.address, user1.address, 1);

  //   await expect(
  //     vwaveTimelock.connect(wallet).setGov(vwave.address, user1.address)
  //   ).to.be.revertedWith("GmxTimelock: action not signalled");

  //   await tokenManager
  //     .connect(wallet)
  //     .setGov(vwaveTimelock.address, vwave.address, user1.address, 1);

  //   await expect(
  //     vwaveTimelock.connect(wallet).setGov(vwave.address, user1.address)
  //   ).to.be.revertedWith("GmxTimelock: action time not yet passed");

  //   await time.increase(6 * 24 * 60 * 60 + 10);
  //   await mine(1);

  //   await expect(
  //     vwaveTimelock.connect(wallet).setGov(vwave.address, user1.address)
  //   ).to.be.revertedWith("GmxTimelock: action time not yet passed");

  //   await time.increase(1 * 24 * 60 * 60 + 10);
  //   await mine(1);

  //   expect(await vwave.gov()).eq(vwaveTimelock.address);
  //   await vwaveTimelock.connect(wallet).setGov(vwave.address, user1.address);
  //   expect(await vwave.gov()).eq(user1.address);
  // });
});
