import type { Candle } from "../core/market";
import type { Instrument } from "../core/instrument";
import { isStreaming } from "../core/universe";
import { decodeFacts, decodeFilings, decodeTickers, earningsReleases, listings, screenRows, decodeFrame, type Fundamentals, type Filing, type ScreenRow } from "../core/sec";
import { parseFactors, mergeFactors, MODELS, type FactorTable, type FactorSet } from "../core/factors";
import { decodeBLS, decodeNYFed, decodeCountries, decodeBulkCSV, type Point, type Country } from "../core/econ";
import { zipFile } from "../core/zip";
import { decodeSicFeed } from "../core/valuation";
import { parseTreasuryCSV, type CurveDay } from "../core/bonds";
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

// MARK: RV (relative valuation)

/** A company's SIC industry from its SEC submissions. */
export const industry = async (c: number) => {
  const s: any = await submissions(c);
  const sic = String(s?.sic ?? "");
  return { sic: SIC.test(sic) ? sic : "", name: String(s?.sicDescription ?? "").slice(0, 120) };   // only a 4-digit code ever reaches a URL
};
const SIC = /^\d{4}$/;
/** Every 10-K filer under one SIC code (EDGAR lists 100 per page). */
export const industryMembers = (sic: string) => once(`sic|${sic}`, async () => {
  if (!SIC.test(sic)) throw new Error("Invalid industry code");
  const out: { cik: number; name: string }[] = [];
  for (let start = 0; start <= 2000; start += 100) {
    const page = decodeSicFeed(await (await relayFetch(`/sec/sic/${sic}?start=${start}`)).text());
    out.push(...page);
    if (page.length < 100) break;
  }
  return out;
});
/** Shares outstanding per CIK: the latest of the last two complete quarter ends. */
export const sharesOutstanding = () => once("shares", async () => {
  const now = new Date(), y = now.getUTCFullYear(), q = Math.floor(now.getUTCMonth() / 3);   // current quarter, 0-based
  const quarters = Array.from({ length: 3 }, (_, k) => { const n = y * 4 + q - 1 - k; return `CY${Math.floor(n / 4)}Q${(n % 4) + 1}I`; });
  const frames = await Promise.all(quarters.map((qq) => json(`/sec/shares/${qq}`).then(decodeFrame).catch(() => new Map<number, number>())));
  const out = new Map<number, number>();
  for (const f of [...frames].reverse()) for (const [k, v] of f) out.set(k, v);   // newest wins
  return out;
});
/** Revenue per CIK for one calendar year (for growth). */
export const revenueFor = (year: number) => once(`rev|${year}`, async () => {
  const fr = (c: string) => json(`/sec/frames/${c}/CY${year}`).then(decodeFrame).catch(() => new Map<number, number>());
  const [a, b] = await Promise.all([fr("Revenues"), fr("RevenueFromContractWithCustomerExcludingAssessedTax")]);
  for (const [k, v] of b) if (!a.has(k)) a.set(k, v);
  return a;
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

// MARK: Treasury curve (GC, YAS)

/** Daily par yield curves for the last `years` calendar years plus this one, oldest first. A missing year is skipped. */
export const treasuryCurves = (years: number) => once(`tsy|${years}`, async () => {
  const now = new Date().getUTCFullYear();
  const files = await Promise.all(Array.from({ length: years + 1 }, (_, k) => now - years + k)
    .map((y) => relayFetch(`/tsy/${y}`).then((r) => r.text()).then(parseTreasuryCSV).catch(() => [] as CurveDay[])));
  const days = files.flat();
  if (!days.length) throw new Error("Treasury yield data is unavailable right now.");
  return days;
});
