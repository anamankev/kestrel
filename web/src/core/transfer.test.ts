import { describe, expect, it } from "vitest";
import { fromSwiftJSON, openBundle, sealBundle, toSwiftJSON, type Bundle } from "./transfer";
import { PaperAccount } from "./paper";
import { AlertBook } from "./alerts";

const LIST = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
function bundle(): Bundle {
  const alerts = new AlertBook();
  alerts.add("BTC-USD", { kind: "above", level: 100_000 }, 64_000, 1_800_000_000_000);
  const account = new PaperAccount();
  account.submit("AAPL", "BUY", 10, { kind: "market" }, { last: 200 }, 1_800_000_000_000);
  account.submit("AAPL", "SELL", 5, { kind: "stopLimit", stop: 180, limit: 179 }, { last: 200 }, 1_800_000_000_000);
  return { exported: 1_800_000_000_000, watchlists: [{ id: "core", name: "CORE", symbols: ["BTC-USD", "^GSPC", "EURUSD=X"] }], activeID: "core", alerts, account };
}

describe("transfer files (ported from KestrelCore TransferTests)", () => {
  it("round-trips with the passphrase and hides the contents", async () => {
    const file = await sealBundle(bundle(), "move my desk please", 1_000);
    expect(new TextDecoder().decode(file).includes("BTC-USD")).toBe(false);
    const back = await openBundle(file, "move my desk please");
    expect(back.account.positions.AAPL.quantity).toBe(10);
    expect(back.account.workingOrders[0].type).toEqual({ kind: "stopLimit", stop: 180, limit: 179 });
    expect(back.alerts.active).toHaveLength(1);
    expect(back.account.orders[0].created).toBe(1_800_000_000_000);
  });
  it("rejects the wrong passphrase, tampering, junk and weak passphrases", async () => {
    const file = await sealBundle(bundle(), "move my desk please", 1_000);
    await expect(openBundle(file, "not the passphrase")).rejects.toThrow(/Wrong passphrase/);
    const bad = file.slice(); bad[bad.length - 5] ^= 0xff;
    await expect(openBundle(bad, "move my desk please")).rejects.toThrow(/Wrong passphrase/);
    await expect(openBundle(new TextEncoder().encode("{}") as any, "move my desk please")).rejects.toThrow(/isn't a Kestrel/);
    await expect(sealBundle(bundle(), "short")).rejects.toThrow(/10 characters/);
  });
  it("rejects hostile iteration counts", async () => {
    const file = await sealBundle(bundle(), "move my desk please", 1_000);
    file.set([0xff, 0xff, 0xff, 0xff], 20);
    await expect(openBundle(file, "move my desk please")).rejects.toThrow(/isn't a Kestrel/);
  });
  it("writes Swift's Codable shapes and UUID ids", () => {
    const j: any = toSwiftJSON(bundle());
    expect(j.watchlists[0].id).toMatch(/^[0-9A-F-]{36}$/); expect(j.activeID).toBe(j.watchlists[0].id);
    expect(j.account.orders[0].type).toEqual({ market: {} });
    expect(j.account.orders[1].type).toEqual({ stopLimit: { stop: 180, limit: 179 } });
    expect(j.alerts.alerts[0].condition).toEqual({ above: { _0: 100_000 } });
    expect(j.account.orders[0].created).toBe(821_692_800); // seconds since 2001
    expect("fillPrice" in j.account.orders[1]).toBe(false); // nil is omitted, as Swift does
  });
  it("reads the app's JSON and validates it like typed input", () => {
    const app = { format: 1, exported: 821692800, activeID: LIST, watchlists: [{ id: LIST, name: "TECH", symbols: ["AAPL", "MSFT"] }],
      alerts: { alerts: [{ id: "1E3B1E6A-5A2C-4D4B-9E3B-7A6C1F0A2B3C", symbol: "NVDA", condition: { movePercent: { _0: 5 } }, created: 821692800 }] },
      account: { cash: 990000, nextID: 2, allowShort: true, positions: { AAPL: { symbol: "AAPL", quantity: 50, averageCost: 200, realized: 0 } },
        orders: [{ id: 1, symbol: "AAPL", side: "BUY", quantity: 50, type: { limit: { _0: 200 } }, created: 821692800, status: "FILLED", fillPrice: 200, updated: 821692800 }],
        fills: [{ id: 1, orderID: 1, symbol: "AAPL", side: "BUY", quantity: 50, price: 200, time: 821692800, realized: 0 }] } };
    const b = fromSwiftJSON(app);
    expect(b.account.orders[0].type).toEqual({ kind: "limit", limit: 200 });
    expect(b.alerts.active[0].condition).toEqual({ kind: "move", percent: 5 });
    expect(b.account.fills[0].time).toBe(1_800_000_000_000);
    expect(() => fromSwiftJSON({ ...app, activeID: "E621E1F8-0000-495A-93FC-0C247A3E6E5F" })).toThrow(/active list/);
    expect(() => fromSwiftJSON({ ...app, watchlists: [{ id: LIST, name: "X", symbols: ["<script>"] }] })).toThrow(/symbol/);
    expect(() => fromSwiftJSON({ ...app, format: 2 })).toThrow(/newer version/);
  });

  it("opens a file exported by the iPad/Mac app", async () => {
    // Sealed by KestrelCore's TransferBundle (TransferTests.bundle(), 1,000 rounds).
    const app = Uint8Array.from(atob("S1hGMb31SXBuQXTtYinCQdpDjWwAAAPoS1NWMf9NFi/TAZtHuvaMFWYR9gFzm6y9A9CuTVLcDtXfqab4Ls2jwqFUKYYaoeQPR8tFEkvL8eczGURQgFyiWog+Fx5K9I2k4cXnDS3tfdLVIDbbScIVwZYK4qR3S1ecNEfXcqDJarV+TuIY0EaHfcFmmBFTlpBTiJbPMiscufzxdeMRQgTj3Dgy7qBq+Lmgm81FGlHUDtiGLkyZdGi3Brj/8Qu8A51C8gYVGi7SFT2+1aWwq/NSROn/gYzXY4HMe7QZdGmUIaeaJm14Ww+Up9z4EwUx0YT78mITS/nNk3/syfJdXr13L0mecylnQJrsbRw47l8Qy7cqiLDCToUc677EsQF3f9wwCxRiYmG/fWw4vmG+50FpWLkyy8SQlButY8LChy/jvZpUQ3aQhvzU9WjtnCu7e3awbYIHvc7YG3Fm+MoTIfJI2ySAeYwqT/gbC/f/A2Sy4u5Q2KFezVNmupoOidww8vmDtZk9S2lIWRjG69WoH+kpS3ZlgSM+XtMnkQl6PX8DOthLPOKSVGABayrVJoxIzV37pQi1L/H4zZsAJXFHcvsLK5DaE8zm+R9Yb9dFt8TE4wf0kVts5HqqnCZo8hheBua8A+xXtWMYzuzBK+EAB4ZBF4ET04v0U2wFXojMOPRDX/XyUh2ku3v73w+TvaMaUCmK5bDWp1vnT8SIqZwKjBTaK61tqrNkYkHsNKFB5mpvR1L81u5RtUa2Akk0radXPQc8SygI+RyDZQG9B3A/qLfKcBM735qwvCnTPPkb00gAxIAzjTG7kBV8DZbjX+Za+A5MxwNaguguA0VQr+YIxevFdLpaCKMzX5YxZC7B1JGU9QqrsJSwXfP2cREg5ApMZ2ZXulSQEOUHq2BnL4tju8yBzNprvKOQnCAsUhs="), (c) => c.charCodeAt(0));
    const b = await openBundle(app, "move my desk please");
    expect(b.account.cash).toBe(12_345);
    expect(b.alerts.active).toHaveLength(1);
    expect(b.alerts.active[0]).toMatchObject({ symbol: "BTC-USD", condition: { kind: "above", level: 100_000 } });
    expect(b.watchlists[0].name).toBe("CORE");
  });
});
