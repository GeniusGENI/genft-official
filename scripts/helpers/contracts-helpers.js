const hre = require("hardhat");
const { getDb, waitForTx } = require("./misc-utils");

const getFirstSigner = async () => (await getEthersSigners())[0];

const getEthersSigners = async () => {
  const ethersSigners = await Promise.all(await hre.ethers.getSigners());
  return ethersSigners;
};

const registerContractInJsonDb = async (contractId, contractInstance) => {
  const currentNetwork = hre.network.name;
  const FORK = process.env.FORK;
  //if (FORK || (currentNetwork !== 'hardhat' && !currentNetwork.includes('coverage'))) {
  console.log(`\n\n*** ${contractId} ***\n`);
  console.log(`Network: ${currentNetwork}`);
  console.log(`contract address: ${contractInstance.address}`);
  if (contractInstance.deployTransaction != undefined) {
    console.log(`tx: ${contractInstance.deployTransaction.hash}`);
    console.log(`deployer address: ${contractInstance.deployTransaction.from}`);
    console.log(`gas price: ${contractInstance.deployTransaction.gasPrice}`);
    console.log(`gas used: ${contractInstance.deployTransaction.gasLimit}`);
  }
  console.log(`\n******`);
  console.log();
  //}

  await getDb()
    .set(`${currentNetwork}.${contractId}`, {
      address: contractInstance.address,
      deployer: contractInstance.deployTransaction != undefined ? contractInstance.deployTransaction.from : "Factory contract",
    })
    .write();
};

const insertContractAddressInDb = async (id, address) =>
  await getDb()
    .set(`${hre.network.name}.${id}`, {
      address,
    })
    .write();

const saveContract = async (
  instance,
  id,
  confirms = 1
) => {

  if (instance.deployTransaction != undefined) {
    await waitForTx(instance.deployTransaction, confirms);
  }
  await registerContractInJsonDb(id, instance);
  return instance;
};

const deployContract = async (contractName, args, signer = null) => {
  const contract = (await (await hre.ethers.getContractFactory(contractName))
    .connect(signer == null ? await getFirstSigner() : signer)
    .deploy(...args));
  // await waitForTx(contract.deployTransaction);
  await registerContractInJsonDb(contractName, contract);
  return contract;
};

const getContract = async (contractName, address = null) => {
  if (address != null)
    return await hre.ethers.getContractAt(contractName, address);
    const addr = (await getDb().get(`${hre.network.name}.${contractName}`).value()).address;
    return await hre.ethers.getContractAt(contractName, addr);
}

const verifyContract = async (
  instance,
  args
) => {
  try {
    await hre.run("verify:verify", {
      address: instance.address,
      constructorArguments: args
    });
  } catch (e) {
    if (typeof e === "string") {
      console.log("Error String: ", e.toUpperCase());
    } else if (e instanceof Error) {
      console.log("Error.message: ", e.message);
    }
    console.log(`\n******`);
    console.log();
  }
  return instance;
};

module.exports = {
  getFirstSigner,
  registerContractInJsonDb,
  getContract,
  verifyContract,
  insertContractAddressInDb,
  saveContract,
  deployContract,
}