import type { Candle } from "../core/market";
import type { Instrument } from "../core/instrument";
import { isStreaming } from "../core/universe";
import { decodeFacts, decodeFilings, decodeTickers, earningsReleases, listings, screenRows, decodeFrame, type Fundamentals, type Filing, type ScreenRow } from "../core/sec";
import { parseFactors, mergeFactors, MODELS, type FactorTable, type FactorSet } from "../core/factors";
import { decodeBLS, decodeNYFed, decodeCountries, decodeBulkCSV, type Point, type Country } from "../core/econ";
import { zipFile } from "../core/zip";
import { chart, relayFetch } from "./relay";

const memo = new Map<string, Promise<unknown>>();
/** Session cache; a failed request is forgotten so the next view retries. */
function once<T>(key: string, f: () => Promise<T>): Promise<T> {
  let p = memo.get(key) as Promise<T> | undefined;
  if (!p) { p = f(); memo.set(key, p); p.catch(() => memo.delete(key)); }
  return p;
}
const json = async (path: string) => (await relayFetch(path)).json();
const bytes = async (path: string) => new Uint8Array(await (await relayFetch(path)).arrayBuffer());

// MARK: Prices

const RANGE_DAYS: Record<string, number> = { "3mo": 92, "6mo": 183, "1y": 366, "2y": 731, "5y": 1827, "10y": 3653 };
/** Daily (or weekly) bars; `adjusted` = total return (dividends reinvested). Coinbase for streaming crypto. */
export function history(i: Instrument, range: string, opts: { weekly?: boolean; adjusted?: boolean } = {}): Promise<Candle[]> {
  return once(`h|${i.symbol}|${range}|${opts.weekly}|${opts.adjusted}`, async () => {
    if (isStreaming(i)) {
      const rows = (await (await fetch(`https://api.exchange.coinbase.com/products/${i.symbol}/candles?granularity=86400`)).json()) as number[][];
      const since = Date.now() - (RANGE_DAYS[range] ?? 366) * 86_400_000;
      return rows.map((k) => ({ time: k[0] * 1000, low: k[1], high: k[2], open: k[3], close: k[4], volume: k[5] })).filter((c) => c.time >= since).reverse();
    }
    return (await chart(i.symbol, range, opts.weekly ? "1wk" : "1d", { adjusted: opts.adjusted, intraday: false })).candles;
  });
}
export const dividends = (i: Instrument) => once(`div|${i.symbol}`, async () => {
  const s = await chart(i.symbol, "10y", "1mo", { adjusted: true });
  return { dividends: s.dividends, price: s.quote.last };
});

// MARK: SEC (the relay sends SEC's required contact)

const tickers = () => once("sec-tickers", async () => decodeTickers(await json("/sec/tickers")));
export async function cik(i: Instrument): Promise<number | null> {
  if (i.assetClass !== "EQUITY") return null;
  return (await tickers()).get(i.ticker)?.cik ?? null;
}
export const fundamentals = (c: number): Promise<Fundamentals> => once(`facts|${c}`, async () => decodeFacts(await json(`/sec/facts/${c}`)));
const submissions = (c: number) => once(`subs|${c}`, () => json(`/sec/submissions/${c}`));
export const filings = async (c: number): Promise<Filing[]> => decodeFilings(await submissions(c));
export const releases = async (c: number): Promise<number[]> => earningsReleases(await submissions(c));

export const screen = (): Promise<{ rows: ScreenRow[]; year: number }> => once("screen", async () => {
  const thisYear = new Date().getUTCFullYear();
  for (const year of [thisYear - 1, thisYear - 2]) {
    try {
      const fr = (c: string, p: string) => json(`/sec/frames/${c}/CY${year}${p}`).then(decodeFrame);
      const [l, revenues, contract, netIncome, assets, liabilities, equity] = await Promise.all([json("/sec/tickers").then(listings), fr("Revenues", ""),
        fr("RevenueFromContractWithCustomerExcludingAssessedTax", ""), fr("NetIncomeLoss", ""), fr("Assets", "Q4I"), fr("Liabilities", "Q4I"), fr("StockholdersEquity", "Q4I")]);
      const [profitLoss, equityNCI, liabEquity] = await Promise.all([fr("ProfitLoss", ""), fr("StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest", "Q4I"), fr("LiabilitiesAndStockholdersEquity", "Q4I")]);
      const rows = screenRows(l, { revenues, contract, netIncome, assets, liabilities, equity, profitLoss, equityNCI, liabEquity });
      if (rows.length >= 500) return { rows, year };
    } catch (e) { if (!String(e).includes("404")) throw e; }
  }
  throw new Error("SEC has no complete annual frames yet");
});

// MARK: Factors, macro, World Bank

const factorFile = (f: FactorSet) => once(`ff|${f}`, async () => parseFactors(new TextDecoder().decode(await zipFile(await bytes(`/french/${f}`)))));
export async function factors(model: string): Promise<FactorTable> {
  const tables = await Promise.all(MODELS[model].sets.map(factorFile));
  return tables.slice(1).reduce(mergeFactors, tables[0]);
}
export const bls = () => once("bls", async () => decodeBLS(await json("/bls")));
export const nyfed = (rate: "effr" | "sofr") => once(`nyfed|${rate}`, async () => {
  const path = rate === "sofr" ? "secured/sofr" : "unsecured/effr";
  return decodeNYFed(await (await fetch(`https://markets.newyorkfed.org/api/rates/${path}/last/60.json`)).json());
});
export const countries = (): Promise<Country[]> => once("wb-countries", async () => decodeCountries(await (await fetch("https://api.worldbank.org/v2/country?format=json&per_page=400")).json()));
export const worldBank = (indicator: string): Promise<Map<string, Point[]>> => once(`wb|${indicator}`, async () =>
  decodeBulkCSV(new TextDecoder().decode(await zipFile(await bytes(`/wb/bulk/${indicator}`), (n) => n.startsWith("API_") && n.endsWith(".csv")))));
