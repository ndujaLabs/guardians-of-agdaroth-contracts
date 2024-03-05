require("dotenv").config();
const hre = require("hardhat");
const ethers = hre.ethers;
const path = require("path");
const EthDeployUtils = require("eth-deploy-utils");
let deployUtils;
const wormholeConfig = require("./config/wormholeConfig");
const { expect } = require("chai");

async function main() {
  deployUtils = new EthDeployUtils(path.resolve(__dirname, ".."), console.log);

  const chainId = await deployUtils.currentChainId();

  const [deployer] = await ethers.getSigners();

  if (chainId === 1337) {
    // on localhost, we deploy the factory
    await deployUtils.deployNickSFactory(deployer);
  }

  let salt = ethers.constants.HashZero;

  const managerProxy = await deployUtils.attach("CrunaManagerProxy");

  // uint256 minDelay,
  //     address[] memory proposers,
  //     address[] memory executors,
  //     address admin,
  //     address _wormholeRelayer,
  //     address _wormhole
  const addr = deployer.address;

  const nft = await deployUtils.deployContractViaNickSFactory(
    deployer,
    "GoA",
    ["uint256", "address[]", "address[]", "address", "address", "address"],
    [60, [addr], [addr], addr, wormholeConfig.standard[chainId][0], wormholeConfig.standard[chainId][1]],
    salt,
  );

  await deployUtils.Tx(
    nft.init(managerProxy.address, BigInt(chainId) * BigInt("1000000"), deployUtils.isMainnet(chainId), { gasLimit: 160000 }),
    "Init nft",
  );

  const factory = await deployUtils.deployProxy("GoAFactory.sol", nft.address, deployer.address);

  const usdc = await deployUtils.attach("USDCoin");
  const usdt = await deployUtils.attach("TetherUSD");

  await deployUtils.Tx(factory.setPrice(3000, { gasLimit: 60000 }), "Setting price");
  await deployUtils.Tx(factory.setStableCoin(usdc.address, true), "Set USDC as stable coin");
  await deployUtils.Tx(factory.setStableCoin(usdt.address, true), "Set USDT as stable coin");

  // discount campaign selling for $9.9
  await deployUtils.Tx(factory.setDiscount(2010), "Set discount");

  await deployUtils.Tx(nft.setFactory(factory.address, { gasLimit: 100000 }), "Set the factory");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
