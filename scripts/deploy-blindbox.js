const { ethers } = require("hardhat");

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing env var: ${name}`);
  }
  return value;
}

async function main() {
  const vrfCoordinator = requiredEnv("SEPOLIA_VRF_COORDINATOR");
  const keyHash = requiredEnv("SEPOLIA_VRF_KEY_HASH");
  const subscriptionId = BigInt(requiredEnv("SEPOLIA_VRF_SUBSCRIPTION_ID"));
  const requestConfirmations = Number(requiredEnv("SEPOLIA_VRF_REQUEST_CONFIRMATIONS"));
  const callbackGasLimit = Number(requiredEnv("SEPOLIA_VRF_CALLBACK_GAS_LIMIT"));
  const nativePayment = requiredEnv("SEPOLIA_VRF_NATIVE_PAYMENT") === "true";
  const rewardTokens = requiredEnv("SEPOLIA_REWARD_TOKENS")
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

  console.log("BlindBox deployed to:", await blindBox.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
