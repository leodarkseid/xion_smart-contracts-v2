/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require("@nomiclabs/hardhat-truffle5");
 require('@nomiclabs/hardhat-ethers');
 require('@openzeppelin/hardhat-upgrades');
 require("hardhat-gas-reporter");
 require('hardhat-contract-sizer');

 const {privateKey, infuraKey} = require('./.secrets.json');

 module.exports = {
   networks: {
     hardhat: {},
     xdai: {
       url: "https://xdai-archive.blockscout.com",
       accounts: [privateKey],
       gasPrice: "auto",
       gas: "auto"
     },
     sokol: {
       url: "https://sokol.poa.network",
       accounts: [privateKey],
       gasPrice: 5000000000,
       gas: "auto"
     },
     goerli: {
       url: "https://goerli.infura.io/v3/" + infuraKey,
       accounts: [privateKey],
       gasPrice: 1000000000,
       gas: "auto"
     },
     bsc: {
       url: "https://bsc-dataseed1.defibit.io",
       accounts: [privateKey],
       gasPrice: 5000000000,
       gas: "auto"
     },
     eth: {
       url: "https://mainnet.infura.io/v3/" + infuraKey,
       accounts: [privateKey],
       gasPrice: 37000000000,
       gas: "auto"
     }
   },
   solidity: "0.7.6",
   gasReporter: {
     enabled: true
   },
   settings: {
     optimizer: {
       enabled: true,
       runs: 200,
     },
   },
 };