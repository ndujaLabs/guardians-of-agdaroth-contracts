require("dotenv").config();
const hre = require("hardhat");
const ethers = hre.ethers;
const path = require("path");
const fs = require("fs-extra");
const EthDeployUtils = require("eth-deploy-utils");
let deployUtils;
const { expect } = require("chai");

async function main() {
  deployUtils = new EthDeployUtils(path.resolve(__dirname, ".."), console.log);

  const chainId = await deployUtils.currentChainId();

  const [deployer] = await ethers.getSigners();
  const manager = await deployUtils.attach("CrunaManagerProxy");
  if (chainId === 1337) {
    console.error("Must use production network to set the bytecode of the contract.");
    process.exit(0);
  }

  const bytecodesPath = path.resolve(__dirname, "../export/deployedBytecodes.json ");

  if (!fs.existsSync(bytecodesPath)) {
    fs.writeFileSync(bytecodesPath, JSON.stringify({}));
  }
  const bytecodes = JSON.parse(fs.readFileSync(bytecodesPath));

  const salt = ethers.constants.HashZero;
  const addr = deployer.address;

  if (!bytecodes.GoA || process.env.OVERRIDE) {
    console.log("Getting bytecode...");
    bytecodes.GoA = await deployUtils.getBytecodeToBeDeployedViaNickSFactory(
      deployer,
      "GoA",
      ["uint256", "address[]", "address[]", "address"],
      [36000, [addr], [addr], addr],
      salt,
    );
    fs.writeFileSync(bytecodesPath, JSON.stringify(bytecodes, null, 2));
    console.log("Done.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
