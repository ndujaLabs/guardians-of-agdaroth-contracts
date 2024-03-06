require("dotenv").config();
const hre = require("hardhat");
const ethers = hre.ethers;
const path = require("path");
const EthDeployUtils = require("eth-deploy-utils");
let deployUtils;
const deployed = require("../export/deployed.json");
const wormholeConfig = require("./config/wormholeConfig");

async function main() {
  deployUtils = new EthDeployUtils(path.resolve(__dirname, ".."), console.log);

  const chainId = await deployUtils.currentChainId();

  let goa = await deployUtils.attach("GoA");

  // init GoA

  let claimer = ethers.constants.AddressZero;
  let reservedTokens = 0;
  if (chainId === 80001) {
    reservedTokens = 1000;
    claimer = "0xdE3735dFBb099d6869C553db195e0F359E0E8e73";
  }
  const network = hre.network.name;
  const crunaManagerProxy = await deployUtils.attach("CrunaManagerProxy");

  await deployUtils.Tx(
    goa.initGoA(
      crunaManagerProxy.address,
      true,
      !wormholeConfig.isMainnet[network],
      reservedTokens,
      claimer,
      wormholeConfig.relayers[network],
      { gasLimit: 190000 },
    ),
    "Init GoA",
  );

  // deploy factory

  const factory = await deployUtils.deployProxy("GoAFactory", goa.address);
  // const factory = await deployUtils.attach("GoAFactory");
  await deployUtils.Tx(factory.setPrice(3700, { gasLimit: 60000 }), "Setting price");

  await deployUtils.Tx(factory.setStableCoin(deployed[chainId].USDCoin, true, { gasLimit: 120000 }), "Set USDC as stable coin");
  await deployUtils.Tx(
    factory.setStableCoin(deployed[chainId].TetherUSD, true, { gasLimit: 120000 }),
    "Set USDT as stable coin",
  );

  await deployUtils.Tx(goa.setFactory(factory.address, { gasLimit: 100000 }), "Set the factory");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
