const { ethers } = require("hardhat");

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing env var: ${name}`);
  }
  return value;
}

async function main() {
  const address = requiredEnv("BLINDBOX_ADDRESS");
  const argBoxType = process.argv.find((arg) => arg.startsWith("--boxType="));
  const rawBoxType = argBoxType ? argBoxType.split("=", 2)[1] : process.env.BOX_TYPE;
  const boxType = Number(rawBoxType);

  if (!Number.isInteger(boxType) || ![0, 1, 2].includes(boxType)) {
    throw new Error("Box type must be 0 (FREE), 1 (SILVER), or 2 (GOLD). Set BOX_TYPE env var or use --boxType=0.");
  }

  const blindBox = await ethers.getContractAt("BlindBox", address);
  const priceOverrides = {
    0: "0.0",
    1: "0.0001",
    2: "0.00001",
  };
  const priceWei = process.env.BOX_PRICE_WEI
    ? BigInt(process.env.BOX_PRICE_WEI)
    : ethers.parseEther(priceOverrides[boxType]);

  const tx = await blindBox.openBox(boxType, { value: priceWei });
  const receipt = await tx.wait();

  const event = receipt.logs.find((log) => log.fragment && log.fragment.name === "BoxOpened");
  if (!event) {
    throw new Error("BoxOpened event not found");
  }

  console.log("RequestId:", event.args.requestId.toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
