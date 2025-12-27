const { ethers } = require("hardhat");

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing env var: ${name}`);
  }
  return value;
}

const ranges = [
  {
    boxType: 0,
    items: [
      { token: "0x0578d8a44db98b23bf096a382e016e29a5ce0ffe", min: "1", max: "3" },
      { token: "0x4ed4e862860bed51a9570b96d89af5e1b0efefed", min: "1", max: "3" },
      { token: "0xac1bd2486aaf3b5c0fc3fd868558b082a531b2b4", min: "5", max: "10" },
      { token: "0x532f27101965dd16442e59d40670faf5ebb142e4", min: "0.1", max: "1" },
      { token: "0x50f88fe97f72cd3e75b9eb4f747f59bceba80d59", min: "0.5", max: "2" },
    ],
  },
  {
    boxType: 1,
    items: [
      { token: "0x0578d8a44db98b23bf096a382e016e29a5ce0ffe", min: "5", max: "10" },
      { token: "0x4ed4e862860bed51a9570b96d89af5e1b0efefed", min: "5", max: "10" },
      { token: "0xac1bd2486aaf3b5c0fc3fd868558b082a531b2b4", min: "10", max: "20" },
      { token: "0x532f27101965dd16442e59d40670faf5ebb142e4", min: "1", max: "2" },
      { token: "0x50f88fe97f72cd3e75b9eb4f747f59bceba80d59", min: "2", max: "5" },
    ],
  },
  {
    boxType: 2,
    items: [
      { token: "0x0578d8a44db98b23bf096a382e016e29a5ce0ffe", min: "10", max: "20" },
      { token: "0x4ed4e862860bed51a9570b96d89af5e1b0efefed", min: "10", max: "20" },
      { token: "0xac1bd2486aaf3b5c0fc3fd868558b082a531b2b4", min: "20", max: "30" },
      { token: "0x532f27101965dd16442e59d40670faf5ebb142e4", min: "2", max: "5" },
      { token: "0x50f88fe97f72cd3e75b9eb4f747f59bceba80d59", min: "5", max: "10" },
    ],
  },
];

async function main() {
  const address = requiredEnv("BLINDBOX_ADDRESS");
  const blindBox = await ethers.getContractAt("BlindBox", address);

  for (const group of ranges) {
    for (const item of group.items) {
      const min = ethers.parseEther(item.min);
      const max = ethers.parseEther(item.max);
      const tx = await blindBox.setTokenRange(group.boxType, item.token, min, max, true);
      await tx.wait();
      console.log(`Set box ${group.boxType} token ${item.token} range ${item.min}-${item.max}`);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
