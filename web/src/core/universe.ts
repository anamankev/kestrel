import type { AssetClass, Instrument, Region } from "./instrument";
import { equities, crypto, indices, currencies, commodities, rates } from "./instruments.generated";

export { equities, crypto, indices, currencies, commodities, rates };
export const all: Instrument[] = [...equities, ...crypto, ...indices, ...currencies, ...commodities, ...rates];

const byTicker = new Map<string, Instrument[]>();
for (const i of all) byTicker.set(i.ticker, [...(byTicker.get(i.ticker) ?? []), i]);
const bySymbol = new Map<string, Instrument>();
for (const i of all) if (!bySymbol.has(i.symbol)) bySymbol.set(i.symbol, i);

/** Coinbase products on the live WebSocket feed. */
export const streamed = new Set(crypto.map((c) => c.symbol));
export const isStreaming = (i: Instrument) => i.assetClass === "CRYPTO" && streamed.has(i.symbol);
export const instrument = (symbol: string) => bySymbol.get(symbol);

/** Yahoo exchange suffixes for listings outside the US. Single letters that are US share classes are absent. */
export const exchangeSuffixes: Record<string, Region> = {
  TO: "AMERICAS", V: "AMERICAS", NE: "AMERICAS", CN: "AMERICAS", SA: "AMERICAS", MX: "AMERICAS", BA: "AMERICAS", SN: "AMERICAS",
  L: "EMEA", IL: "EMEA", DE: "EMEA", F: "EMEA", PA: "EMEA", AS: "EMEA", BR: "EMEA", LS: "EMEA", MI: "EMEA", MC: "EMEA", SW: "EMEA",
  VI: "EMEA", ST: "EMEA", OL: "EMEA", CO: "EMEA", HE: "EMEA", IR: "EMEA", WA: "EMEA", AT: "EMEA", IS: "EMEA", JO: "EMEA", TA: "EMEA",
  SR: "EMEA", QA: "EMEA", PR: "EMEA", BD: "EMEA", T: "ASIA/PACIFIC", HK: "ASIA/PACIFIC", SS: "ASIA/PACIFIC", SZ: "ASIA/PACIFIC",
  KS: "ASIA/PACIFIC", KQ: "ASIA/PACIFIC", TW: "ASIA/PACIFIC", TWO: "ASIA/PACIFIC", AX: "ASIA/PACIFIC", NZ: "ASIA/PACIFIC",
  SI: "ASIA/PACIFIC", NS: "ASIA/PACIFIC", BO: "ASIA/PACIFIC", JK: "ASIA/PACIFIC", BK: "ASIA/PACIFIC", KL: "ASIA/PACIFIC",
};

const iso = new Set(Intl.supportedValuesOf ? Intl.supportedValuesOf("currency") : []);
/** A six-letter token made of two ISO currency codes (GBPJPY): an FX cross. */
export const isCurrencyPair = (t: string) => t.length === 6 && /^[A-Z]{6}$/.test(t) && iso.has(t.slice(0, 3)) && iso.has(t.slice(3));

/** What to type so `resolve` returns this instrument again. */
export function token(i: Instrument): string {
  switch (i.assetClass) {
    case "CURNCY": return i.ticker;
    case "CRYPTO": return streamed.has(i.symbol) ? i.ticker : i.symbol;
    case "INDEX": case "CMDTY": case "GOVT": return byTicker.has(i.ticker) ? i.ticker : i.symbol;
    default: return i.symbol;
  }
}

/** Resolves a typed token (AAPL, BTC, SPX, 7203.T, GBPJPY, ES=F, ^STI) into an instrument. */
export function resolve(raw: string, hint?: AssetClass): Instrument | undefined {
  const upper = raw.toUpperCase();
  const tok = upper.replaceAll("/", "-").replaceAll(".", "-");
  if (hint === "CRYPTO") {
    const c = bySymbol.get(tok.endsWith("-USD") ? tok : `${tok}-USD`);
    if (c) return c;
  }
  const matches = byTicker.get(tok);
  if (matches) return matches.find((m) => m.assetClass === hint) ?? matches[0];
  const s = bySymbol.get(tok) ?? bySymbol.get(upper);
  if (s) return s;
  if (hint === "CURNCY") { const f = bySymbol.get(`${tok}=X`); if (f) return f; }
  const pair = upper.endsWith("=X") ? upper.slice(0, -2) : upper;
  if ((!hint || hint === "CURNCY") && isCurrencyPair(pair)) return { symbol: `${pair}=X`, ticker: pair, name: `${pair.slice(0, 3)} / ${pair.slice(3)}`, assetClass: "CURNCY" };
  if (upper.endsWith("=F") && upper.length <= 10) return { symbol: upper, ticker: upper, name: upper, assetClass: "CMDTY" };
  if (upper.startsWith("^") && upper.length <= 12 && /^\^[A-Z0-9.]+$/.test(upper)) return { symbol: upper, ticker: upper, name: upper, assetClass: "INDEX" };
  if ((hint === "CRYPTO" || upper.endsWith("-USD")) && /^[A-Z0-9]{2,12}(-USD)?$/.test(tok)) {
    const base = tok.endsWith("-USD") ? tok.slice(0, -4) : tok;
    return { symbol: `${base}-USD`, ticker: hint === "CRYPTO" ? base : `${base}-USD`, name: base, assetClass: "CRYPTO" };
  }
  if (!hint || hint === "EQUITY") {
    const dot = upper.lastIndexOf(".");
    const region = dot > 0 ? exchangeSuffixes[upper.slice(dot + 1)] : undefined;
    if (region && /^[A-Z0-9][A-Z0-9\-&]{0,11}\.[A-Z]{1,3}$/.test(upper)) return { symbol: upper, ticker: upper, name: upper, assetClass: "EQUITY", region };
    if (/^[A-Z][A-Z0-9-]{0,7}$/.test(tok)) return { symbol: tok, ticker: tok, name: tok, assetClass: "EQUITY", region: "AMERICAS" };
  }
  return undefined;
}

/** Prefix search on ticker, then substring search on name. */
export function search(query: string, limit = 6): Instrument[] {
  const q = query.toUpperCase();
  if (!q) return [];
  const prefix = all.filter((i) => i.ticker.startsWith(q));
  const name = all.filter((i) => !i.ticker.startsWith(q) && i.name.toUpperCase().includes(q));
  return [...prefix, ...name].slice(0, limit);
}

export const currencyGroups = (): [string, Instrument[]][] => {
  const g10 = new Set(["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "USDCAD", "NZDUSD", "DXY"]);
  const crosses = new Set(["EURGBP", "EURJPY", "GBPJPY"]);
  return [["G10 & DOLLAR INDEX", currencies.filter((c) => g10.has(c.ticker))], ["CROSSES", currencies.filter((c) => crosses.has(c.ticker))],
    ["EMERGING MARKETS", currencies.filter((c) => !g10.has(c.ticker) && !crosses.has(c.ticker))]];
};

export const commodityGroups = (): [string, Instrument[]][] =>
  ([["ENERGY", ["CL1", "CO1", "NG1", "HO1", "XB1"]], ["METALS", ["GC1", "SI1", "HG1", "PL1", "PA1"]],
    ["AGRICULTURE & LIVESTOCK", ["C1", "W1", "S1", "KC1", "SB1", "CT1", "CC1", "LC1", "LH1"]],
    ["EQUITY INDEX & RATE FUTURES", ["ES1", "NQ1", "DM1", "RTY1", "TY1", "US1"]]] as [string, string[]][])
    .map(([n, ts]) => [n, ts.map((t) => commodities.find((c) => c.ticker === t)!).filter(Boolean)]);
