const { ethers } = require("hardhat");
const hre = require("hardhat");

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing env var: ${name}`);
  }
  return value;
}

async function main() {
  const network = hre.network.name;
  const prefix = network === "base" ? "BASE" : network === "base-sepolia" ? "BASE_SEPOLIA" : "SEPOLIA";
  const vrfCoordinator = requiredEnv(`${prefix}_VRF_COORDINATOR`);
  const keyHash = requiredEnv(`${prefix}_VRF_KEY_HASH`);
  const subscriptionId = BigInt(requiredEnv(`${prefix}_VRF_SUBSCRIPTION_ID`));
  const requestConfirmations = Number(requiredEnv(`${prefix}_VRF_REQUEST_CONFIRMATIONS`));
  const callbackGasLimit = Number(requiredEnv(`${prefix}_VRF_CALLBACK_GAS_LIMIT`));
  const nativePayment = requiredEnv(`${prefix}_VRF_NATIVE_PAYMENT`) === "true";
  const rewardTokens = requiredEnv(`${prefix}_REWARD_TOKENS`)
    .split(",")
    .map((token) => token.trim())
    .filter((token) => token.length > 0);

  const BlindBox = await ethers.getContractFactory("BlindBox");
  const blindBox = await BlindBox.deploy(
    vrfCoordinator,
    keyHash,
    subscriptionId,
    requestConfirmations,
    callbackGasLimit,
    nativePayment,
    rewardTokens
  );
  await blindBox.waitForDeployment();

  const address = await blindBox.getAddress();
  console.log("BlindBox deployed to:", address);

  const signer = (await ethers.getSigners())[0];

  async function sendWithNonce(txFn) {
    const maxAttempts = 3;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      const nonce = await signer.getNonce("pending");
      try {
        const tx = await txFn(nonce);
        return tx;
      } catch (error) {
        const message = (error && error.message) || "";
        if (!message.includes("nonce too low") || attempt === maxAttempts) {
          throw error;
        }
        await new Promise((resolve) => setTimeout(resolve, 1500));
      }
    }
  }

  const tokenRanges = [
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

  for (const group of tokenRanges) {
    for (const item of group.items) {
      const min = ethers.parseEther(item.min);
      const max = ethers.parseEther(item.max);
      const tx = await sendWithNonce((nonce) =>
        blindBox
          .connect(signer)
          .setTokenRange(group.boxType, item.token, min, max, true, { nonce })
      );
      await tx.wait();
      console.log(`Set box ${group.boxType} token ${item.token} range ${item.min}-${item.max}`);
    }
  }

  const confirmTarget = Number(process.env.VERIFY_CONFIRMATIONS || 2);
  if (confirmTarget > 0) {
    const receipt = await blindBox.deploymentTransaction().wait(confirmTarget);
    console.log(`Confirmed in block ${receipt.blockNumber}`);
  }

  const verifyArgs = {
    address,
    constructorArguments: [
      vrfCoordinator,
      keyHash,
      subscriptionId,
      requestConfirmations,
      callbackGasLimit,
      nativePayment,
      rewardTokens,
    ],
  };

  const networkName = hre.network.name;
  const baseApi = {
    base: {
      basescan: {
        apiURL: "https://api.basescan.org/api",
        browserURL: "https://basescan.org",
        apiKey: process.env.BASESCAN_API_KEY || process.env.ETHERSCAN_API_KEY,
      },
      blockscout: {
        apiURL: "https://base.blockscout.com/api",
        browserURL: "https://base.blockscout.com",
        apiKey: process.env.BLOCKSCOUT_API_KEY,
      },
    },
    "base-sepolia": {
      basescan: {
        apiURL: "https://api-sepolia.basescan.org/api",
        browserURL: "https://sepolia.basescan.org",
        apiKey: process.env.BASESCAN_API_KEY || process.env.ETHERSCAN_API_KEY,
      },
      blockscout: {
        apiURL: "https://base-sepolia.blockscout.com/api",
        browserURL: "https://base-sepolia.blockscout.com",
        apiKey: process.env.BLOCKSCOUT_API_KEY,
      },
    },
  };

  async function verifyWithExplorer(tag, chainConfig) {
    if (!chainConfig || !chainConfig.apiKey) {
      console.log(`Skipping ${tag} verification (missing API key).`);
      return;
    }

    const original = {
      customChains: hre.config.etherscan.customChains,
      apiKey: hre.config.etherscan.apiKey,
    };

    hre.config.etherscan.customChains = [
      {
        network: networkName,
        chainId: networkName === "base" ? 8453 : 84532,
        urls: { apiURL: chainConfig.apiURL, browserURL: chainConfig.browserURL },
      },
    ];
    hre.config.etherscan.apiKey = {
      ...original.apiKey,
      [networkName]: chainConfig.apiKey,
    };

    try {
      await hre.run("verify:verify", verifyArgs);
      console.log(`Verified on ${tag}.`);
    } catch (error) {
      console.warn(`${tag} verification failed or already verified.`);
      console.warn(error.message || error);
    } finally {
      hre.config.etherscan.customChains = original.customChains;
      hre.config.etherscan.apiKey = original.apiKey;
    }
  }

  if (networkName === "base" || networkName === "base-sepolia") {
    const config = baseApi[networkName];
    await verifyWithExplorer("BaseScan", config.basescan);
    await verifyWithExplorer("Blockscout", config.blockscout);
  } else {
    try {
      await hre.run("verify:verify", verifyArgs);
      console.log("Verified on Etherscan.");
    } catch (error) {
      console.warn("Verification failed or already verified.");
      console.warn(error.message || error);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
