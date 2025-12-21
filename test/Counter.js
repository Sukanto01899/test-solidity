const { expect } = require("chai");

describe("Counter", function () {
  async function deployCounter(initialValue = 5) {
    const Counter = await ethers.getContractFactory("Counter");
    const counter = await Counter.deploy(initialValue);
    await counter.waitForDeployment();
    return counter;
  }

  it("stores the initial value", async function () {
    const counter = await deployCounter(12);
    expect(await counter.current()).to.equal(12);
  });

  it("increments the value", async function () {
    const counter = await deployCounter(0);
    await counter.increment();
    expect(await counter.current()).to.equal(1);
  });

  it("sets the value", async function () {
    const counter = await deployCounter(3);
    await counter.set(42);
    expect(await counter.current()).to.equal(42);
  });
});
