// Constructor args for BlindBox on Base
module.exports = [
  "0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634", // vrfCoordinator
  "0x00b81b5a830cb0a4009fbd8904de511e28631e62ce5ad231373d3cdad373ccab", // keyHash
  "112053198502214273438529944727181118341065542141336855367193183985457343165064", // subscriptionId
  3, // requestConfirmations
  200000, // callbackGasLimit
  false, // nativePayment
  [
    "0x0578d8a44db98b23bf096a382e016e29a5ce0ffe",
    "0x4ed4e862860bed51a9570b96d89af5e1b0efefed",
    "0xac1bd2486aaf3b5c0fc3fd868558b082a531b2b4",
    "0x532f27101965dd16442e59d40670faf5ebb142e4",
    "0x50f88fe97f72cd3e75b9eb4f747f59bceba80d59",
  ],
];
