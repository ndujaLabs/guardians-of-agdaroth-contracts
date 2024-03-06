require("dotenv").config();
const hre = require("hardhat");
const ethers = hre.ethers;
const path = require("path");
const EthDeployUtils = require("eth-deploy-utils");
let deployUtils;
const fs = require("fs-extra");

async function main() {
  deployUtils = new EthDeployUtils(path.resolve(__dirname, ".."), console.log);

  const chainId = await deployUtils.currentChainId();

  const [deployer] = await ethers.getSigners();

  if (chainId === 1337) {
    // on localhost, we deploy the factory
    await deployUtils.deployNickSFactory(deployer);
  }

  const salt = ethers.constants.HashZero;
  const bytecodesPath = path.resolve(__dirname, "../export/deployedBytecodes.json ");
  const bytecodes = JSON.parse(fs.readFileSync(bytecodesPath));

  await deployUtils.deployBytecodeViaNickSFactory(deployer, "GoA", bytecodes.GoA, salt);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
