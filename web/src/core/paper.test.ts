import { describe, expect, it } from "vitest";
import { PaperAccount } from "./paper";
import { AlertBook } from "./alerts";

const t = (last: number, bid?: number, ask?: number) => ({ last, bid, ask });

describe("PaperAccount", () => {
  it("fills market buys at the ask and sells at the bid", () => {
    const a = new PaperAccount();
    a.submit("BTC-USD", "BUY", 2, { kind: "market" }, t(100, 99, 101));
    expect(a.cash).toBe(1_000_000 - 202);
    a.submit("BTC-USD", "SELL", 2, { kind: "market" }, t(110, 109, 111));
    expect(a.realizedPnL).toBe(16);
    expect(a.openPositions).toHaveLength(0);
  });
  it("rests limits, reserves cash and fills on the cross with price improvement", () => {
    const a = new PaperAccount();
    const o = a.submit("X", "BUY", 10, { kind: "limit", limit: 50 }, t(55, 54.9, 55.1));
    expect(o.status).toBe("WORKING");
    expect(a.buyingPower).toBe(1_000_000 - 500);
    a.mark("X", t(49, 48.9, 49.1));
    expect(a.orders[0].status).toBe("FILLED");
    expect(a.orders[0].fillPrice).toBe(49.1);
  });
  it("triggers stops on the last trade and rejects stops through the market", () => {
    const a = new PaperAccount();
    a.submit("X", "BUY", 10, { kind: "market" }, t(100));
    expect(() => a.submit("X", "SELL", 10, { kind: "stop", stop: 105 }, t(100))).toThrow(/below the last/);
    a.submit("X", "SELL", 10, { kind: "stop", stop: 95 }, t(100));
    a.mark("X", t(96)); expect(a.workingOrders).toHaveLength(1);
    a.mark("X", t(94)); expect(a.openPositions).toHaveLength(0);
    expect(a.realizedPnL).toBe(-60);
  });
  it("holds 150% margin on shorts and releases it on cover", () => {
    const a = new PaperAccount();
    a.submit("X", "SELL", 100, { kind: "market" }, t(10));
    expect(a.positions.X.quantity).toBe(-100);
    expect(a.cash).toBe(1_001_000);
    expect(a.buyingPower).toBe(1_001_000 - 1500);
    a.submit("X", "BUY", 100, { kind: "market" }, t(8));
    expect(a.realizedPnL).toBe(200);
    expect(a.buyingPower).toBe(1_000_200);
  });
  it("rejects bad input and over-spending, and never shorts options", () => {
    const a = new PaperAccount();
    expect(() => a.submit("X", "BUY", 0, { kind: "market" }, t(1))).toThrow();
    expect(() => a.submit("X", "BUY", 1, { kind: "market" })).toThrow(/No market/);
    expect(() => a.submit("X", "BUY", 1e6, { kind: "market" }, t(10))).toThrow(/Insufficient cash/);
    expect(() => a.submit("BTC-27DEC26-100000-C", "SELL", 1, { kind: "market" }, t(10))).toThrow(/long premium/);
  });
  it("keeps cash exact over many small fills and survives a save round trip", () => {
    const a = new PaperAccount();
    for (let k = 0; k < 1000; k++) a.submit("X", "BUY", 0.1, { kind: "market" }, t(0.3));
    expect(a.cash).toBe(999_970);
    const b = PaperAccount.from(JSON.parse(JSON.stringify(a)));
    expect(b.cash).toBe(a.cash); expect(b.positions.X.quantity).toBe(100); expect(b.nextID).toBe(1001);
    expect(PaperAccount.from({ cash: "x" }).cash).toBe(1_000_000);
  });
});

describe("AlertBook", () => {
  it("fires once and refuses levels already through", () => {
    const b = new AlertBook();
    expect(() => b.add("X", { kind: "above", level: 90 }, 100)).toThrow(/already through/);
    b.add("X", { kind: "above", level: 110 }, 100, 0, "a");
    b.add("X", { kind: "move", percent: 5 }, 100, 0, "m");
    expect(b.evaluate("X", 105, 4)).toHaveLength(0);
    expect(b.evaluate("X", 111, 6).map((a) => a.id).sort()).toEqual(["a", "m"]);
    expect(b.evaluate("X", 120, 9)).toHaveLength(0);
    expect(AlertBook.from(JSON.parse(JSON.stringify(b))).history).toHaveLength(2);
  });
});
