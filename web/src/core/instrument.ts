/** Yellow-key asset classes; values are what a user types on the command line. */
export type AssetClass = "EQUITY" | "CRYPTO" | "INDEX" | "CURNCY" | "CMDTY" | "GOVT" | "OPTION";
export type Region = "AMERICAS" | "EMEA" | "ASIA/PACIFIC";

export interface Instrument {
  /** Data-source symbol: a Yahoo symbol (^GSPC, EURUSD=X) or a Coinbase product (BTC-USD). */
  symbol: string;
  /** What the user types and sees (SPX, EURUSD, BTC). */
  ticker: string;
  name: string;
  assetClass: AssetClass;
  region?: Region;
}

export const eq = (s: string, n: string): Instrument => ({ symbol: s, ticker: s, name: n, assetClass: "EQUITY", region: "AMERICAS" });
export const cx = (base: string, n: string): Instrument => ({ symbol: `${base}-USD`, ticker: base, name: n, assetClass: "CRYPTO" });
export const ix = (s: string, t: string, n: string, r: Region): Instrument => ({ symbol: s, ticker: t, name: n, assetClass: "INDEX", region: r });
export const fx = (pair: string, n: string): Instrument => ({ symbol: `${pair}=X`, ticker: pair, name: n, assetClass: "CURNCY" });
export const cm = (s: string, t: string, n: string): Instrument => ({ symbol: s, ticker: t, name: n, assetClass: "CMDTY" });
export const rt = (s: string, t: string, n: string): Instrument => ({ symbol: s, ticker: t, name: n, assetClass: "GOVT", region: "AMERICAS" });
