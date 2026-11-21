/** DATA: every source Kestrel reads, what it powers, and how to check it cheaply. Mirrors KestrelCore/DataSources.swift. */
export type Probe = { kind: "relay"; path: string } | { kind: "direct"; url: string } | { kind: "feed" };
export interface Source { id: string; name: string; powers: string; probe: Probe }

const year = () => new Date().getUTCFullYear();
export const SOURCES: Source[] = [
  { id: "coinbase-ws", name: "Coinbase live feed", powers: "Live crypto prices, DEPTH, TAS, GP (crypto)", probe: { kind: "feed" } },
  { id: "coinbase", name: "Coinbase market data", powers: "Crypto charts and history", probe: { kind: "direct", url: "https://api.exchange.coinbase.com/products/BTC-USD/ticker" } },
  { id: "yahoo", name: "Yahoo Finance (delayed)", powers: "Stocks, indices, FX, futures, rates: W, GP, HP, BETA, SEAS, MOST", probe: { kind: "relay", path: "/yahoo/spark?symbols=SPY&range=1d&interval=5m" } },
  { id: "sec", name: "SEC EDGAR", powers: "FA, DCF, RV, EQS, EVTS, ERN, AI", probe: { kind: "relay", path: "/sec/tickers" } },
  { id: "treasury", name: "U.S. Treasury", powers: "GC, YAS", probe: { kind: "relay", path: `/tsy/${year()}` } },
  { id: "bls", name: "Bureau of Labor Statistics", powers: "ECO inflation and jobs", probe: { kind: "relay", path: "/bls" } },
  { id: "nyfed", name: "New York Fed", powers: "ECO policy rates (EFFR, SOFR)", probe: { kind: "direct", url: "https://markets.newyorkfed.org/api/rates/unsecured/effr/last/1.json" } },
  { id: "news", name: "News feeds (CNBC, MarketWatch, CoinDesk, Yahoo)", powers: "TOP, CN, AI headlines", probe: { kind: "relay", path: "/rss/cnbc" } },
  { id: "deribit", name: "Deribit", powers: "OMON, OSA crypto options", probe: { kind: "direct", url: "https://www.deribit.com/api/v2/public/get_index_price?index_name=btc_usd" } },
  { id: "worldbank", name: "World Bank", powers: "ECST country data", probe: { kind: "direct", url: "https://api.worldbank.org/v2/country/USA?format=json" } },
  { id: "french", name: "Ken French data library", powers: "FACT factor models", probe: { kind: "relay", path: "/french/F-F_Momentum_Factor_daily_CSV.zip" } },
];

/** Which source a relay path belongs to (for passive tracking of every request the app makes). */
export function sourceOfPath(path: string): string | undefined {
  const head = path.split("/")[1] ?? "";
  return ({ yahoo: "yahoo", sec: "sec", tsy: "treasury", bls: "bls", rss: "news", french: "french", wb: "worldbank" } as Record<string, string>)[head];
}

export type Status = "OK" | "SLOW" | "DOWN";
/** Over 3 seconds counts as slow; any failure is down. */
export const classify = (ok: boolean, ms: number): Status => (!ok ? "DOWN" : ms > 3000 ? "SLOW" : "OK");
