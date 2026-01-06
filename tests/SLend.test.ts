
import { describe, expect, it } from "vitest";
import { tx } from "@hirosystems/clarinet-sdk";
import { Cl, type ClarityValue } from "@stacks/transactions";

const CONTRACT_NAME = "SLend";
const accounts = simnet.getAccounts();

const getAccount = (name: string) => {
  const account = accounts.get(name);
  if (!account) throw new Error(`Missing simnet account: ${name}`);
  return account;
};

const owner = accounts.get("deployer") ?? getAccount("wallet_1");
const wallet2 = getAccount("wallet_2");
const wallet3 = getAccount("wallet_3");
const wallet4 = getAccount("wallet_4");

const mineCall = (sender: string, method: string, args: ClarityValue[] = []) =>
  simnet.mineBlock([tx.callPublicFn(CONTRACT_NAME, method, args, sender)])[0];

const readOnly = (
  method: string,
  args: ClarityValue[] = [],
  sender: string = owner,
) => simnet.callReadOnlyFn(CONTRACT_NAME, method, args, sender);

describe("SLend core flows", () => {
  it("handles deposits and standard withdrawals", () => {
    const amount = 200_000n;
    const withdrawAmount = 50_000n;

    const deposit = mineCall(wallet2, "deposit", [Cl.uint(amount)]);
    expect(deposit.result).toBeOk(Cl.stringAscii("Deposited"));

    const balanceAfterDeposit = readOnly("get-balance", [
      Cl.principal(wallet2),
    ]);
    expect(balanceAfterDeposit.result).toBeUint(amount);

    const withdraw = mineCall(wallet2, "withdraw", [Cl.uint(withdrawAmount)]);
    expect(withdraw.result).toBeErr(Cl.uint(2));

    const balanceAfterWithdraw = readOnly("get-balance", [
      Cl.principal(wallet2),
    ]);
    expect(balanceAfterWithdraw.result).toBeUint(amount);
  });

  it("enforces lock periods via can-withdraw checks", () => {
    const amount = 120_000n;
    const lockBlocks = 5;

    const deposit = mineCall(wallet3, "deposit-with-lock", [
      Cl.uint(amount),
      Cl.uint(lockBlocks),
    ]);
    expect(deposit.result).toBeOk(
      Cl.stringAscii("Time-locked deposit created"),
    );

    const canWithdrawEarly = readOnly("can-withdraw", [
      Cl.principal(wallet3),
    ]);
    expect(canWithdrawEarly.result).toBeBool(false);

    simnet.mineEmptyBlocks(lockBlocks);
    const canWithdrawLate = readOnly("can-withdraw", [Cl.principal(wallet3)]);
    expect(canWithdrawLate.result).toBeBool(true);
  });

  it("records emergency withdrawal attempts", () => {
    const amount = 80_000n;

    const deposit = mineCall(wallet3, "deposit-with-lock", [
      Cl.uint(amount),
      Cl.uint(10),
    ]);
    expect(deposit.result).toBeOk(
      Cl.stringAscii("Time-locked deposit created"),
    );

    const emergency = mineCall(wallet3, "emergency-withdraw", [Cl.uint(amount)]);
    expect(emergency.result).toBeErr(Cl.uint(2));

    const balanceAfterEmergency = readOnly("get-balance", [
      Cl.principal(wallet3),
    ]);
    expect(balanceAfterEmergency.result).toBeUint(amount);
  });

  it("records referral deposits after referrer balance is set", () => {
    const referrerDeposit = mineCall(wallet4, "deposit", [Cl.uint(50_000n)]);
    expect(referrerDeposit.result).toBeOk(Cl.stringAscii("Deposited"));

    const referredDeposit = mineCall(wallet3, "deposit-with-referral", [
      Cl.uint(25_000n),
      Cl.principal(wallet4),
    ]);
    expect(referredDeposit.result).toBeOk(
      Cl.stringAscii("Deposited with referral"),
    );

    const referrer = readOnly("get-referrer", [Cl.principal(wallet3)]);
    expect(referrer.result).toBeSome(Cl.principal(wallet4));
  });

  it("executes a governance proposal after reaching confirmations", () => {
    const nonOwnerAdd = mineCall(wallet2, "add-owner", [
      Cl.principal(wallet3),
    ]);
    expect(nonOwnerAdd.result).toBeErr(Cl.uint(13));

    const addOwner = mineCall(owner, "add-owner", [Cl.principal(wallet2)]);
    expect(addOwner.result).toBeOk(Cl.bool(true));

    const setConfirmations = mineCall(owner, "set-required-confirmations", [
      Cl.uint(2),
    ]);
    expect(setConfirmations.result).toBeOk(Cl.bool(true));

    const newLimit = 500_000n;
    const proposal = mineCall(owner, "create-proposal", [
      Cl.stringAscii("set-limit"),
      Cl.principal(owner),
      Cl.uint(newLimit),
    ]);
    expect(proposal.result).toBeOk(Cl.uint(1));

    const confirm = mineCall(wallet2, "confirm-proposal", [Cl.uint(1)]);
    expect(confirm.result).toBeOk(Cl.bool(true));

    const dailyLimit = readOnly("get-daily-limit");
    expect(dailyLimit.result).toBeUint(newLimit);
  });

  it("manages oracle updates and dynamic rate toggles", () => {
    const oracle = wallet4;

    const setOracle = mineCall(owner, "set-oracle", [Cl.principal(oracle)]);
    expect(setOracle.result).toBeOk(Cl.bool(true));

    const oracleAddress = readOnly("get-oracle-address");
    expect(oracleAddress.result).toBeSome(Cl.principal(oracle));

    const priceUpdate = mineCall(oracle, "update-stx-price", [
      Cl.uint(200_000),
    ]);
    expect(priceUpdate.result).toBeOk(Cl.bool(true));

    const price = readOnly("get-stx-price");
    expect(price.result).toBeUint(200_000);

    const toggle = mineCall(owner, "toggle-dynamic-rates");
    expect(toggle.result).toBeOk(Cl.bool(true));

    const dynamicRates = readOnly("is-dynamic-rates-enabled");
    expect(dynamicRates.result).toBeBool(true);
  });
});
