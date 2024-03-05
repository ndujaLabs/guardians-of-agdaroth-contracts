const { expect } = require("chai");
const { ethers } = require("hardhat");
const { toChecksumAddress } = require("ethereumjs-util");
const EthDeployUtils = require("eth-deploy-utils");
const deployUtils = new EthDeployUtils();

const CrunaTestUtils = require("./helpers/CrunaTestUtils");

const { amount, normalize, addr0, getChainId, getTimestamp, executeAndReturnGasUsed, bytesX } = require("./helpers");
const wormholeConfig = require("../scripts/config/wormholeConfig");

describe("Integration test", function () {
  let crunaManagerProxy;
  let goa;
  let factory;
  let usdc;
  let deployer, bob, alice, fred, mike;

  const wormholeRelayer = "0x27428DD2d3DD32A4D7f7C497eAaa23130d894911";
  const wormhole = wormholeConfig.mainnets.matic[2];

  before(async function () {
    [deployer, bob, alice, fred, mike] = await ethers.getSigners();
    await CrunaTestUtils.deployCanonical(deployer);
  });

  async function initAndDeploy(getMock = "") {
    crunaManagerProxy = await CrunaTestUtils.deployManager(deployer);
    goa = await deployUtils.deploy("GoA" + getMock, deployer.address, wormholeRelayer, wormhole);
    await goa.init(crunaManagerProxy.address, true, false, 31337 * 1e6, 31337 * 1e6 + 10001);
    factory = await deployUtils.deployProxy("GoAFactory", goa.address);
    await goa.setFactory(factory.address);
    usdc = await deployUtils.deploy("USDCoin", deployer.address);

    await usdc.mint(deployer.address, normalize("900"));
    await usdc.mint(bob.address, normalize("900"));
    await usdc.mint(fred.address, normalize("900"));
    await usdc.mint(alice.address, normalize("900"));
    await usdc.mint(mike.address, normalize("600"));

    await expect(factory.setPrice(990)).to.emit(factory, "PriceSet").withArgs(990);
    await expect(factory.setStableCoin(usdc.address, true)).to.emit(factory, "StableCoinSet").withArgs(usdc.address, true);
  }

  //here we test the contract
  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should buy a vault", async function () {
    let price = await factory.finalPrice(usdc.address);
    await usdc.approve(factory.address, price);
    let tokenId = 31337 * 1e6;
    await expect(factory.buy(usdc.address, [tokenId]))
      .to.emit(goa, "Transfer")
      .withArgs(addr0, deployer.address, tokenId);

    await expect(factory.buy(usdc.address, [tokenId - 100])).revertedWith("InvalidTokenId");

    await expect(factory.buy(usdc.address, [tokenId + 2e6])).revertedWith("InvalidTokenId");
  });

  it.only("should calculate expected gas limit when receiving the Wormhole message", async function () {
    await initAndDeploy("Mock");
    let tokenId = 31337 * 1e6 + 100;
    let payload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [deployer.address, tokenId]);
    await goa.receiveWormholeMessages(payload, [], bytesX(32, goa.address), 0, bytesX(32, 0));
    // expect(gasUsed.div(1e9).toString()).equal("134530");
  });

  async function buyVault(token, tokenIDs, buyer) {
    let price = await factory.finalPrice(token.address);
    await token.connect(buyer).approve(factory.address, price.mul(tokenIDs.length));

    await expect(factory.connect(buyer).buy(token.address, tokenIDs))
      .to.emit(goa, "Transfer")
      .withArgs(addr0, buyer.address, tokenIDs[0])
      .to.emit(token, "Transfer")
      .withArgs(buyer.address, factory.address, price.mul(tokenIDs.length));
  }

  it("should allow bob and alice to purchase some vaults", async function () {
    let nextTokenId = 31337 * 1e6;
    await buyVault(usdc, [nextTokenId, nextTokenId + 1], bob);
    await buyVault(usdc, [nextTokenId + 2, nextTokenId + 3], alice);

    let price = await factory.finalPrice(usdc.address);
    expect(price.toString()).to.equal("9900000000000000000");

    await expect(factory.withdrawProceeds(fred.address, usdc.address, normalize("10")))
      .to.emit(usdc, "Transfer")
      .withArgs(factory.address, fred.address, normalize("10"));

    await expect(factory.withdrawProceeds(fred.address, usdc.address, 0))
      .to.emit(usdc, "Transfer")
      .withArgs(factory.address, fred.address, amount("29.6"));

    const managerAddress = await goa.managerOf(nextTokenId);
    const manager = await ethers.getContractAt("CrunaManager", managerAddress);

    const selector = await CrunaTestUtils.selectorId("ICrunaManager", "setProtector");
    const chainId = await getChainId();
    const ts = (await getTimestamp()) - 100;

    let signature = (
      await CrunaTestUtils.signRequest(
        selector,
        bob.address,
        alice.address,
        goa.address,
        nextTokenId,
        1,
        0,
        0,
        ts,
        3600,
        chainId,
        alice.address,
        manager,
      )
    )[0];

    // set Alice as first Bob's protector
    await expect(manager.connect(bob).setProtector(alice.address, true, ts, 3600, signature))
      .to.emit(manager, "ProtectorChange")
      .withArgs(nextTokenId, alice.address, true)
      .to.emit(goa, "Locked")
      .withArgs(nextTokenId, true);
  });

  it("should remove a stableCoin when active is false", async function () {
    await expect(factory.setStableCoin(usdc.address, false)).to.emit(factory, "StableCoinSet").withArgs(usdc.address, false);

    const updatedStableCoins = await factory.getStableCoins();
    expect(updatedStableCoins).to.not.include(usdc.address);
  });
});
