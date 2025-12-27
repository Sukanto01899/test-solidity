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

  async function openBoxAndGetRequestId(blindBox, boxType, user, valueOverride) {
    const price = await blindBox.boxPrices(boxType);
    const value = valueOverride !== undefined ? valueOverride : price;
    const tx = await blindBox.connect(user).openBox(boxType, { value });
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

  it("requires exact or higher fee and refunds excess", async function () {
    const { blindBox, user } = await deployFixture();
    const price = await blindBox.boxPrices(1);

    await expect(
      blindBox.connect(user).openBox(1, { value: price - 1n })
    ).to.be.revertedWith("INSUFFICIENT_FEE");

    const overpay = price + ethers.parseEther("0.00002");
    const balanceBefore = await ethers.provider.getBalance(user.address);
    const tx = await blindBox.connect(user).openBox(1, { value: overpay });
    const receipt = await tx.wait();
    const gasCost = receipt.gasUsed * receipt.gasPrice;
    const balanceAfter = await ethers.provider.getBalance(user.address);
    expect(balanceBefore - balanceAfter - gasCost).to.equal(price);
  });

  it("allows owner to update box price", async function () {
    const { blindBox, owner } = await deployFixture();
    const newPrice = ethers.parseEther("0.0002");
    await expect(blindBox.connect(owner).setBoxPrice(2, newPrice))
      .to.emit(blindBox, "BoxPriceUpdated")
      .withArgs(2, newPrice);
    expect(await blindBox.boxPrices(2)).to.equal(newPrice);
  });

  it("allows owner to cancel pending opens", async function () {
    const { blindBox, user, owner } = await deployFixture();
    const requestId = await openBoxAndGetRequestId(blindBox, 0, user);
    expect(await blindBox.pendingRequestCount()).to.equal(1);

    await expect(blindBox.connect(owner).cancelPendingOpen(requestId))
      .to.emit(blindBox, "PendingOpenCanceled")
      .withArgs(requestId, user.address, 0);
    expect(await blindBox.pendingRequestCount()).to.equal(0);
  });

  it("rejects cancelPendingOpen from non-owner", async function () {
    const { blindBox, user, other } = await deployFixture();
    const requestId = await openBoxAndGetRequestId(blindBox, 0, user);
    await expect(blindBox.connect(other).cancelPendingOpen(requestId)).to.be.revertedWith("Not owner");
  });

  it("allows owner to withdraw native balance", async function () {
    const { blindBox, owner, user } = await deployFixture();
    const price = await blindBox.boxPrices(1);
    await blindBox.connect(user).openBox(1, { value: price });

    const balanceBefore = await ethers.provider.getBalance(owner.address);
    const tx = await blindBox.connect(owner).emergencyWithdraw(ethers.ZeroAddress, owner.address, price);
    const receipt = await tx.wait();
    const gasCost = receipt.gasUsed * receipt.gasPrice;
    const balanceAfter = await ethers.provider.getBalance(owner.address);
    expect(balanceAfter - balanceBefore + gasCost).to.equal(price);
  });

  it("fuzzes reward bounds for silver and gold", async function () {
    const { blindBox, coordinator, tokenA, tokenB, tokenC, user } = await deployFixture();
    const contractAddress = await blindBox.getAddress();

    const mintAmount = ethers.parseEther("100000");
    await tokenA.mint(contractAddress, mintAmount);
    await tokenB.mint(contractAddress, mintAmount);
    await tokenC.mint(contractAddress, mintAmount);

    const iterations = 5;
    for (let i = 0; i < iterations; i += 1) {
      const boxType = i % 2 === 0 ? 1 : 2;
      const config = await blindBox.getBoxConfig(boxType);
      const requestId = await openBoxAndGetRequestId(blindBox, boxType, user);
      await coordinator.fulfillRandomWords(contractAddress, requestId, 1000 + i);

      const [tokens, amounts] = await blindBox.getPendingRewards(user.address);
      expect(tokens.length).to.equal(config.numTokensToReward);
      expect(amounts.length).to.equal(config.numTokensToReward);

      const uniqueTokens = new Set(tokens.map((t) => t.toLowerCase()));
      expect(uniqueTokens.size).to.equal(tokens.length);

      for (const amount of amounts) {
        expect(amount).to.be.greaterThanOrEqual(config.minAmount);
        expect(amount).to.be.lessThanOrEqual(config.maxAmount);
      }

      await expect(blindBox.connect(user).claimAll()).to.emit(blindBox, "RewardClaimed");
    }
  });

  it("fuzzes fee enforcement for paid box types", async function () {
    const { blindBox, user } = await deployFixture();
    const iterations = 10;

    for (let i = 0; i < iterations; i += 1) {
      const boxType = i % 2 === 0 ? 1 : 2;
      const price = await blindBox.boxPrices(boxType);
      const tooLow = price > 0n ? price - 1n : 0n;

      await expect(
        blindBox.connect(user).openBox(boxType, { value: tooLow })
      ).to.be.revertedWith("INSUFFICIENT_FEE");

      await expect(blindBox.connect(user).openBox(boxType, { value: price }))
        .to.emit(blindBox, "BoxOpened");
    }
  });

  it("returns last reward via getLastReward", async function () {
    const { blindBox, coordinator, tokenA, tokenB, tokenC, user } = await deployFixture();
    const contractAddress = await blindBox.getAddress();

    const mintAmount = ethers.parseEther("10000");
    await tokenA.mint(contractAddress, mintAmount);
    await tokenB.mint(contractAddress, mintAmount);
    await tokenC.mint(contractAddress, mintAmount);

    const requestId = await openBoxAndGetRequestId(blindBox, 0, user);
    await coordinator.fulfillRandomWords(contractAddress, requestId, 4242);

    const [lastToken, lastAmount] = await blindBox.getLastReward(user.address);
    expect(lastToken).to.not.equal(ethers.ZeroAddress);
    expect(lastAmount).to.be.greaterThan(0);

    const pending = await blindBox.pendingRewards(user.address, lastToken);
    expect(pending).to.equal(lastAmount);
  });
});
