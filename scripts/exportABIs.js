const fs = require("fs-extra");
const path = require("path");

async function main() {
  const ABIs = {
    contracts: {},
  };

  function abi(name, folder, rename) {
    let source = path.resolve(__dirname, `../artifacts/${folder ? folder + "/" : ""}${name}.sol/${name}.json`);
    let json = require(source);
    ABIs.contracts[rename || name] = json.abi;
  }
  abi("GoA", "contracts");
  abi("GoAFactory", "contracts");

  await fs.writeFile(path.resolve(__dirname, "../export/GoA.json"), JSON.stringify(ABIs, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
