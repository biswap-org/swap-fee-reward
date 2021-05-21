const SwapFeeReward = artifacts.require("SwapFeeReward");
const Oracle = artifacts.require("Oracle");

module.exports = async function (deployer) {

  
  await deployer.deploy(Oracle, "0x4e138eC1E171D9FB0d9D700F717996d0de9492af", "0xfccd8edabb6ca6652a1af8bd3b26a22704650ba24bc27b11a514bc00c836853b");
  let instanceOracle = await Oracle.deployed();
  console.log(instanceOracle.address);


  await deployer.deploy(
    SwapFeeReward,
      "0x4e138eC1E171D9FB0d9D700F717996d0de9492af",
      "0xdf135E2989585D50E4f254E86715e7711e046c0F",
      "0xfccd8edabb6ca6652a1af8bd3b26a22704650ba24bc27b11a514bc00c836853b",
      "0x18749C94C5775A9B294ffF2e4c35f8CeEf6F9BdC",
      instanceOracle.address,
      "0x8eBbD8eA391f74032391e2970BCE1351C16b6801"
    );
  let instanceSwapFeeReward = await SwapFeeReward.deployed();



  // "0x4e138eC1E171D9FB0d9D700F717996d0de9492af",
  //   "0xfccd8edabb6ca6652a1af8bd3b26a22704650ba24bc27b11a514bc00c836853b"
  // let instanceOracle = deployer.deploy(
  //   SwapMining,
  //   "0x4e138eC1E171D9FB0d9D700F717996d0de9492af",
  //   "0xdf135E2989585D50E4f254E86715e7711e046c0F",
  //   "fccd8edabb6ca6652a1af8bd3b26a22704650ba24bc27b11a514bc00c836853b",
  //       IBswToken _bswToken,
  //       IOracle _Oracle,
  //       address _targetToken
  // );
};
//