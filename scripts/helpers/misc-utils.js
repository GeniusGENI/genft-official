const {BigNumber} = require('bignumber.js');
const low = require('lowdb');
const FileSync = require('lowdb/adapters/FileSync');
const hre = require('hardhat');
const { ethers } = require('hardhat');

const getDb = () => low(new FileSync('./data/contracts-genius.json'));
const sleep = (milliseconds) => {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
};

const timeLatest = async () => {
  const block = await hre.ethers.provider.getBlock('latest');
  return block.timestamp;
};

const advanceBlock = async (timestamp) =>
  await hre.ethers.provider.send('evm_mine', [timestamp]);

const addDays = async (days) => {
  await hre.ethers.provider.send('evm_increaseTime', [days * 24 * 60 * 60]);
  await hre.ethers.provider.send('evm_mine', []);
};

const increaseTime = async (secondsToIncrease) => {
  await hre.ethers.provider.send('evm_increaseTime', [secondsToIncrease]);
  await hre.ethers.provider.send('evm_mine', []);
};

const tenExponent = (digits) => {
  return (new BigNumber(10)).pow(digits);
};

const posE = (number, digits = 18, decimals = -1) => {
  number = number || "0";
  const bn = new BigNumber(number);
  const exp = tenExponent(digits);
  const outcome = bn.multipliedBy(exp);
  if (decimals !== -1) {
    // @ts-ignore
    return outcome.toFixed(decimals);
  }
  return outcome;
};

const negE = (number, digits = 18, decimals = -1) => {
  number = number || "0";
  const bn = new BigNumber(number);
  const exp = tenExponent(digits);
  const outcome = bn.div(exp);
  if (decimals !== -1) {
    return outcome.toFixed(decimals);
  }
  return outcome;
};

// Workaround for time travel tests bug: https://github.com/Tonyhaenn/hh-time-travel/blob/0161d993065a0b7585ec5a043af2eb4b654498b8/test/test.js#L12
const advanceTimeAndBlock = async function (forwardTime) {
  const currentBlockNumber = await hre.ethers.provider.getBlockNumber();
  const currentBlock = await hre.ethers.provider.getBlock(currentBlockNumber);

  if (currentBlock === null) {
    /* Workaround for https://github.com/nomiclabs/hardhat/issues/1183
     */
    await hre.ethers.provider.send('evm_increaseTime', [forwardTime]);
    await hre.ethers.provider.send('evm_mine', []);
    //Set the next blocktime back to 15 seconds
    await hre.ethers.provider.send('evm_increaseTime', [15]);
    return;
  }
  const currentTime = currentBlock.timestamp;
  const futureTime = currentTime + forwardTime;
  await hre.ethers.provider.send('evm_setNextBlockTimestamp', [futureTime]);
  await hre.ethers.provider.send('evm_mine', []);
};

const waitForTx = async (tx, confirms = 1) => await tx.wait(confirms);

module.exports = {
  getDb,
  posE,
  negE,
  addDays,
  waitForTx,
}