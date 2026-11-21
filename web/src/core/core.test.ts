import { describe, expect, test } from "vitest";
import { resolve, token, isStreaming, currencies, all, currencyGroups, commodityGroups } from "./universe";
import { parse, suggestions, CommandError, functions } from "./command";
import { decodeSearch, decodeChart, decodeSpark } from "./yahoo";
import { decode } from "./coinbase";
import { sma, rsi, bollinger } from "./indicators";
import { OrderBook } from "./market";
import { clock, price, signed } from "./format";

describe("universe", () => {
  test("listings outside the US keep their exchange", () => {
    expect(resolve("7203.t")).toMatchObject({ symbol: "7203.T", assetClass: "EQUITY", region: "ASIA/PACIFIC" });
    expect(resolve("VOD.L")?.region).toBe("EMEA");
    expect(resolve("BRK.B")?.symbol).toBe("BRK-B");
    expect(resolve("3")).toBeUndefined();
  });
  test("any currency, future, index and coin resolves", () => {
    expect(resolve("GBPJPY")).toMatchObject({ symbol: "GBPJPY=X", assetClass: "CURNCY" });
    expect(resolve("EURUSD")).toBe(currencies[0]);
    expect(resolve("ES=F")?.assetClass).toBe("CMDTY");
    expect(resolve("^STI")?.assetClass).toBe("INDEX");
    const pepe = resolve("PEPE", "CRYPTO")!;
    expect(pepe.symbol).toBe("PEPE-USD");
    expect(isStreaming(pepe)).toBe(false);
    expect(isStreaming(resolve("BTC")!)).toBe(true);
  });
  test("tokens round-trip", () => {
    for (const t of ["7203.T", "GBPJPY", "ES=F", "^STI", "SPX", "BTC", "DOGE-USD", "AAPL", "PEPE-USD"]) {
      const i = resolve(t)!;
      expect(resolve(token(i))).toEqual(i);
    }
  });
  test("boards are complete", () => {
    expect(all.length).toBe(120);
    expect(currencyGroups().flatMap(([, l]) => l).length).toBe(20);
    expect(commodityGroups().flatMap(([, l]) => l).length).toBe(25);
  });
});

describe("command parser", () => {
  test("parses securities and functions in any order", () => {
    expect(parse("AAPL GP")).toMatchObject({ fn: "GP", instrument: { symbol: "AAPL" } });
    expect(parse("gp aapl <GO>").fn).toBe("GP");
    expect(parse("AAPL").fn).toBe("DES");
    expect(parse("SOL BUY")).toMatchObject({ fn: "TRADE", side: "BUY" });
    expect(parse("SECF nestle sa")).toEqual({ fn: "SECF", query: "NESTLE SA" });
    expect(parse("ECST JAPAN").query).toBe("JAPAN");
    expect(parse("GP", resolve("NVDA")).instrument?.symbol).toBe("NVDA");
    expect(() => parse("GP")).toThrow(CommandError);
    expect(() => parse("")).toThrow(CommandError);
    expect(() => parse("X".repeat(80))).toThrow(CommandError);
  });
  test("every function parses", () => {
    expect(functions.length).toBe(44);   // 38 + RV, SEAS, GC, YAS, LEARN, DCF
    for (const f of functions) expect(parse(f.needsSecurity ? `AAPL ${f.code}` : f.code).fn).toBe(f.code);
  });
  test("suggestions", () => {
    expect(suggestions("AA")[0].completion).toBe("AAPL");
    expect(suggestions("AAPL G").map((s) => s.completion)).toContain("AAPL GP");
    expect(suggestions("3")).toEqual([]);
  });
});

describe("decoders", () => {
  test("Yahoo search maps every asset class", () => {
    const hits = decodeSearch({ quotes: [
      { symbol: "7203.T", longname: "Toyota Motor Corporation", quoteType: "EQUITY", exchDisp: "Tokyo" },
      { symbol: "^GSPC", shortname: "S&P 500", quoteType: "INDEX" },
      { symbol: "GBPJPY=X", quoteType: "CURRENCY" },
      { symbol: "ES=F", quoteType: "FUTURE" },
      { symbol: "BTC-EUR", quoteType: "CRYPTOCURRENCY" },
      { symbol: "AAPL250117C00200000", quoteType: "OPTION" },
    ] });
    expect(hits.map((h) => h.instrument.assetClass)).toEqual(["EQUITY", "INDEX", "CURNCY", "CMDTY"]);
    expect(hits[1].token).toBe("SPX");
  });
  test("Yahoo chart with adjusted closes and dividends", () => {
    const json = { chart: { result: [{ meta: { regularMarketPrice: 99 }, timestamp: [1, 2], events: { dividends: { 2: { amount: 0.5, date: 2 } } },
      indicators: { quote: [{ open: [100, 100], high: [101, 101], low: [99, 99], close: [100, 100], volume: [1, 1] }], adjclose: [{ adjclose: [99.5, 100] }] } }] } };
    expect(decodeChart(json, false, false).candles[0].close).toBe(100);
    expect(decodeChart(json, false, true).candles[0].close).toBe(99.5);
    expect(decodeChart(json).dividends).toEqual([{ date: 2000, amount: 0.5 }]);
  });
  test("Yahoo spark batch", () => {
    const m = decodeSpark({ AAPL: { timestamp: [1, 2], previousClose: 100, close: [101, null, 103] }, BAD: { close: [] } });
    expect(m.get("AAPL")?.quote).toMatchObject({ last: 103, previousClose: 100, high: 103, low: 101, time: 2000 });
    expect(m.get("AAPL")?.closes).toEqual([101, 103]);
    expect(m.has("BAD")).toBe(false);
  });
  test("Coinbase ticker, book and trades", () => {
    const t = decode({ channel: "ticker", events: [{ tickers: [{ product_id: "BTC-USD", price: "100", price_percent_chg_24_h: "25", best_bid: "99.5" }] }] }, 7);
    expect(t[0]).toMatchObject({ kind: "ticker", product: "BTC-USD", quote: { last: 100, previousClose: 80, bid: 99.5, time: 7 } });
    const b = decode({ channel: "l2_data", events: [{ type: "snapshot", product_id: "BTC-USD", updates: [{ side: "bid", price_level: "1", new_quantity: "2" }] }] });
    expect(b[0]).toMatchObject({ kind: "book", snapshot: true, updates: [{ side: "bid", price: 1, size: 2 }] });
    const tr = decode({ channel: "market_trades", events: [{ trades: [{ trade_id: "1", product_id: "ETH-USD", price: "2", size: "3", side: "SELL", time: "2026-01-01T00:00:00.123456789Z" }] }] });
    expect(tr[0]).toMatchObject({ kind: "trades", prints: [{ side: "BUY", price: 2 }] });
  });
});

describe("indicators and book", () => {
  test("sma, rsi, bollinger", () => {
    expect(sma([1, 2, 3, 4], 2)).toEqual([null, 1.5, 2.5, 3.5]);
    expect(rsi([1, 2, 3, 4, 5], 2)[4]).toBe(100);
    expect(bollinger([2, 2, 2], 3)[2]).toEqual({ mid: 2, upper: 2, lower: 2 });
  });
  test("order book ladder", () => {
    const b = new OrderBook();
    for (const [p, s] of [[100, 1], [99, 2], [98, 3]]) b.apply("bid", p, s);
    b.apply("ask", 101, 1); b.apply("ask", 102, 1); b.apply("bid", 98, 0);
    const l = b.ladder(2);
    expect(l.bids.map((x) => x.price)).toEqual([100, 99]);
    expect(l.bids[1].cumulative).toBe(3);
    expect(b.spread).toBe(1);
  });
});

describe("format", () => {
  test("24-hour clocks and price precision", () => {
    expect(clock(Date.UTC(2026, 10, 18, 0, 53, 23), "America/New_York")).toBe("19:53:23");
    expect(price(86.55, "CMDTY")).toBe("86.55");
    expect(signed(0.0028, 2.51)).toBe("+0.00");
    expect(price(1.10174, "CURNCY")).toBe("1.1017");
  });
});
