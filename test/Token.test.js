import { EVM_REVERT, tokens } from "./helpers";

require("chai").use(require("chai-as-promised")).should();

const Token = artifacts.require("./Token");

contract("Token", ([deployer, receiver, exchange]) => {
  let token;
  const name = "Rated Crypto";
  const symbol = "RATED";
  const decimals = "18";
  const totalSupply = tokens(1000000);

  beforeEach(async () => {
    token = await Token.new();
  });

  describe("deployment", () => {
    it("tracks the name", async () => {
      const result = await token.name();
      result.should.equal(name);
    });

    it("tracks the symbol", async () => {
      const result = await token.symbol();
      result.should.equal(symbol);
    });

    it("tracks the decimals", async () => {
      const result = await token.decimals();
      result.toString().should.equal(decimals);
    });

    it("tracks the total supply", async () => {
      const result = await token.totalSupply();
      result.toString().should.equal(totalSupply.toString());
    });

    it("assign total supply to the deployer", async () => {
      const result = await token.balanceOf(deployer);
      result.toString().should.equal(totalSupply.toString());
    });
  });

  describe("sending tokens", () => {
    let amount;
    let result;

    describe("success", async () => {
      beforeEach(async () => {
        amount = tokens(100);
        result = await token.transfer(receiver, amount, { from: deployer });
      });

      it("transfer token balances", async () => {
        let balanceOf;
        balanceOf = await token.balanceOf(deployer);
        balanceOf.toString().should.equal(tokens(999900).toString());
        balanceOf = await token.balanceOf(receiver);
        balanceOf.toString().should.equal(tokens(100).toString());
      });

      it("emits a Transfer event", async () => {
        const log = result.logs[0];
        log.event.should.equal("Transfer");
        const event = log.args;
        event.from.toString().should.equal(deployer, "from is correct");
        event.to.should.equal(receiver, "to is correct");
        event.value
          .toString()
          .should.equal(amount.toString(), "value is correct");
      });
    });

    describe("failure", async () => {
      it("rejects insufficient balance", async () => {
        let invalidAmount;
        invalidAmount = tokens(100000000); // 100 million - more than token supply
        await token
          .transfer(receiver, invalidAmount, { from: deployer })
          .should.be.rejectedWith(EVM_REVERT);
        invalidAmount = tokens(10); // receiver has no tokens
        await token
          .transfer(deployer, invalidAmount, { from: receiver })
          .should.be.rejectedWith(EVM_REVERT);
      });

      it("rejects invalid recipients", async () => {
        await token.transfer(0x0, amount, { from: deployer }).should.be
          .rejected;
      });
    });
  });

  describe("approving tokens", () => {
    let amount;
    let result;

    beforeEach(async () => {
      amount = tokens(100);
      result = await token.approve(exchange, amount, { from: deployer });
    });

    describe("success", async () => {
      it("allocates an allowance for delegated token spending on exchange", async () => {
        const allowance = await token.allowance(deployer, exchange);
        allowance.toString().should.equal(amount.toString());
      });

      it("emits an Approval event", async () => {
        const log = result.logs[0];
        log.event.should.equal("Approval");
        const event = log.args;
        event.owner.toString().should.equal(deployer, "from is correct");
        event.spender.should.equal(exchange, "spender is correct");
        event.value
          .toString()
          .should.equal(amount.toString(), "value is correct");
      });
    });

    describe("failure", async () => {
      it("rejects invalid spenders", async () => {
        await token.transfer(0x0, amount, { from: deployer }).should.be
          .rejected;
      });
    });
  });

  describe("delegated token transfers", () => {
    let amount;
    let result;

    beforeEach(async () => {
      amount = tokens(100);
      await token.approve(exchange, amount, { from: deployer });
    });

    describe("success", async () => {
      beforeEach(async () => {
        result = await token.transferFrom(deployer, receiver, amount, {
          from: exchange,
        });
      });

      it("transfer token balances", async () => {
        let balanceOf;
        balanceOf = await token.balanceOf(deployer);
        balanceOf.toString().should.equal(tokens(999900).toString());
        balanceOf = await token.balanceOf(receiver);
        balanceOf.toString().should.equal(tokens(100).toString());
      });

      it("emits a Transfer event", async () => {
        const log = result.logs[0];
        log.event.should.equal("Transfer");
        const event = log.args;
        event.from.toString().should.equal(deployer, "from is correct");
        event.to.should.equal(receiver, "to is correct");
        event.value
          .toString()
          .should.equal(amount.toString(), "value is correct");
      });

      it("resets the allowance", async () => {
        const allowance = await token.allowance(deployer, exchange);
        allowance.toString().should.equal("0");
      });
    });

    describe("failure", async () => {
      it("rejects insufficient amount", async () => {
        // Attempt transfer too many tokens
        const invalidAmount = tokens(100000000); // 100 million - more than token supply
        await token
          .transferFrom(deployer, receiver, invalidAmount, { from: exchange })
          .should.be.rejectedWith(EVM_REVERT);
      });

      it("rejects invalid recipients", async () => {
        await token.transfer(0x0, amount, { from: deployer }).should.be
          .rejected;
      });
    });
  });
});
