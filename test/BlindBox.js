const { expect } = require("chai");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("BlindBox", function () {
  async function deployFixture() {
    const [owner, user, other] = await ethers.getSigners();

    const MockVRFCoordinator = await ethers.getContractFactory("MockVRFCoordinator");
    const coordinator = await MockVRFCoordinator.deploy();
    await coordinator.waitForDeployment();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const tokenA = await MockERC20.deploy("TokenA", "TKA");
    const tokenB = await MockERC20.deploy("TokenB", "TKB");
    const tokenC = await MockERC20.deploy("TokenC", "TKC");
    await Promise.all([
      tokenA.waitForDeployment(),
      tokenB.waitForDeployment(),
      tokenC.waitForDeployment(),
    ]);

    const BlindBox = await ethers.getContractFactory("BlindBox");
    const blindBox = await BlindBox.deploy(
      await coordinator.getAddress(),
      "0x" + "11".repeat(32),
      1,
      3,
      200000,
      false,
      [await tokenA.getAddress(), await tokenB.getAddress(), await tokenC.getAddress()]
    );
    await blindBox.waitForDeployment();

    return { owner, user, other, coordinator, blindBox, tokenA, tokenB, tokenC };
  }

  async function openBoxAndGetRequestId(blindBox, boxType, user) {
    const tx = await blindBox.connect(user).openBox(boxType);
    const receipt = await tx.wait();
    const event = receipt.logs.find((log) => log.fragment && log.fragment.name === "BoxOpened");
    return event.args.requestId;
  }

  it("queues rewards on fulfill and allows claim", async function () {
    const { blindBox, coordinator, tokenA, tokenB, tokenC, user } = await deployFixture();
    const contractAddress = await blindBox.getAddress();

    const mintAmount = ethers.parseEther("10000");
    await tokenA.mint(contractAddress, mintAmount);
    await tokenB.mint(contractAddress, mintAmount);
    await tokenC.mint(contractAddress, mintAmount);

    const requestId = await openBoxAndGetRequestId(blindBox, 0, user);
    await coordinator.fulfillRandomWords(contractAddress, requestId, 1234);

    const [tokens, amounts] = await blindBox.getPendingRewards(user.address);
    expect(tokens.length).to.equal(1);
    expect(amounts.length).to.equal(1);
    expect(amounts[0]).to.be.greaterThanOrEqual(ethers.parseEther("100"));
    expect(amounts[0]).to.be.lessThanOrEqual(ethers.parseEther("250"));

    let rewardToken = tokenA;
    if (tokens[0] === (await tokenB.getAddress())) {
      rewardToken = tokenB;
    } else if (tokens[0] === (await tokenC.getAddress())) {
      rewardToken = tokenC;
    }

    await expect(() => blindBox.connect(user).claim(tokens[0])).to.changeTokenBalance(
      rewardToken,
      user,
      amounts[0]
    );

    const remaining = await blindBox.pendingRewards(user.address, tokens[0]);
    expect(remaining).to.equal(0);
  });

  it("enforces free box cooldown", async function () {
    const { blindBox, coordinator, tokenA, tokenB, tokenC, user } = await deployFixture();
    const contractAddress = await blindBox.getAddress();

    const mintAmount = ethers.parseEther("10000");
    await tokenA.mint(contractAddress, mintAmount);
    await tokenB.mint(contractAddress, mintAmount);
    await tokenC.mint(contractAddress, mintAmount);

    const requestId = await openBoxAndGetRequestId(blindBox, 0, user);
    await coordinator.fulfillRandomWords(contractAddress, requestId, 999);

    await expect(blindBox.connect(user).openBox(0)).to.be.revertedWith("FREE_BOX_COOLDOWN");

    await time.increase(24 * 60 * 60 + 1);
    await expect(blindBox.connect(user).openBox(0)).to.emit(blindBox, "BoxOpened");
  });

  it("selects multiple rewards for silver boxes", async function () {
    const { blindBox, coordinator, tokenA, tokenB, tokenC, user } = await deployFixture();
    const contractAddress = await blindBox.getAddress();

    const mintAmount = ethers.parseEther("10000");
    await tokenA.mint(contractAddress, mintAmount);
    await tokenB.mint(contractAddress, mintAmount);
    await tokenC.mint(contractAddress, mintAmount);

    const requestId = await openBoxAndGetRequestId(blindBox, 1, user);
    await coordinator.fulfillRandomWords(contractAddress, requestId, 2024);

    const [tokens, amounts] = await blindBox.getPendingRewards(user.address);
    expect(tokens.length).to.equal(2);
    expect(amounts.length).to.equal(2);
    for (const amount of amounts) {
      expect(amount).to.be.greaterThanOrEqual(ethers.parseEther("500"));
      expect(amount).to.be.lessThanOrEqual(ethers.parseEther("1000"));
    }
  });

  it("rejects fulfill calls from non-coordinator", async function () {
    const { blindBox, other, user } = await deployFixture();
    const requestId = await openBoxAndGetRequestId(blindBox, 0, user);
    await expect(
      blindBox.connect(other).rawFulfillRandomWords(requestId, [1])
    ).to.be.revertedWith("Only coordinator");
  });
});
