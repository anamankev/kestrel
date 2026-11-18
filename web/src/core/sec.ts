/** SEC EDGAR decoders (Fundamentals.swift, Macro.swift SECFilings, Research.swift SECFrames). */

export interface FiscalYear {
  year: number; periodEnd: number;
  revenue?: number; grossProfit?: number; operatingIncome?: number; netIncome?: number; epsDiluted?: number;
  operatingCashFlow?: number; capex?: number; cash?: number; longTermDebt?: number; equity?: number; assets?: number; liabilities?: number;
}
export interface Fundamentals { name: string; cik: number; years: FiscalYear[]; sharesOutstanding?: number; lastFiled?: number }
const ratio = (a?: number, b?: number) => (a == null || b == null || b === 0 ? undefined : a / b);
export const fyMetrics = (f: FiscalYear) => ({
  freeCashFlow: f.operatingCashFlow == null ? undefined : f.operatingCashFlow - (f.capex ?? 0),
  grossMargin: ratio(f.grossProfit, f.revenue), operatingMargin: ratio(f.operatingIncome, f.revenue), netMargin: ratio(f.netIncome, f.revenue),
  roe: ratio(f.netIncome, f.equity), debtToEquity: ratio(f.longTermDebt, f.equity),
});

const day = (s?: string) => (s ? Date.parse(s + "T00:00:00Z") : NaN);
type K = Exclude<keyof FiscalYear, "year" | "periodEnd">;
const FLOWS: [K, string[]][] = [
  ["revenue", ["RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues", "SalesRevenueNet", "RevenueFromContractWithCustomerIncludingAssessedTax"]],
  ["grossProfit", ["GrossProfit"]], ["operatingIncome", ["OperatingIncomeLoss"]], ["netIncome", ["NetIncomeLoss", "ProfitLoss"]],
  ["epsDiluted", ["EarningsPerShareDiluted", "EarningsPerShareBasicAndDiluted"]], ["operatingCashFlow", ["NetCashProvidedByUsedInOperatingActivities"]],
  ["capex", ["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets"]],
];
const INSTANTS: [K, string[]][] = [
  ["cash", ["CashAndCashEquivalentsAtCarryingValue", "CashCashEquivalentsRestrictedCashAndRestrictedCashEquivalents"]],
  ["longTermDebt", ["LongTermDebt", "LongTermDebtNoncurrent"]], ["equity", ["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"]],
  ["assets", ["Assets"]], ["liabilities", ["Liabilities"]],
];

function annual(gaap: any, names: string[], flow: boolean): Map<number, [number, number]> {
  const out = new Map<number, [number, number]>();
  for (const name of names) {
    const units = gaap?.[name]?.units;
    const facts: any[] = units?.USD ?? units?.["USD/shares"];
    if (!facts) continue;
    const mine = new Map<number, [number, number]>();
    for (const f of facts) {
      if (f.form !== "10-K" && f.form !== "10-K/A") continue;
      const end = day(f.end);
      if (!Number.isFinite(end)) continue;
      if (flow) { const s = day(f.start); const len = (end - s) / 86_400_000; if (!(len >= 330 && len <= 400)) continue; }
      const filed = Number.isFinite(day(f.filed)) ? day(f.filed) : 0;
      const have = mine.get(end);
      if (!have || have[1] <= filed) mine.set(end, [f.val, filed]);
    }
    for (const [end, v] of mine) if (!out.has(end)) out.set(end, v);
  }
  return out;
}

/** SEC "company facts" → the last `limit` fiscal years from 10-Ks. */
export function decodeFacts(json: any, limit = 5): Fundamentals {
  const gaap = json?.facts?.["us-gaap"] ?? {};
  const byEnd = new Map<number, FiscalYear>();
  let lastFiled: number | undefined;
  for (const [k, names] of FLOWS) for (const [end, [v, filed]] of annual(gaap, names, true)) {
    const fy = byEnd.get(end) ?? { year: new Date(end).getUTCFullYear(), periodEnd: end };
    fy[k] = v; byEnd.set(end, fy);
    if (filed > (lastFiled ?? 0)) lastFiled = filed;
  }
  for (const [k, names] of INSTANTS) { const vals = annual(gaap, names, false); for (const [end, fy] of byEnd) { const v = vals.get(end); if (v) fy[k] = v[0]; } }
  const years = [...byEnd.values()].filter((y) => y.revenue != null || y.netIncome != null).sort((a, b) => a.periodEnd - b.periodEnd);
  const sh: any[] = json?.facts?.dei?.EntityCommonStockSharesOutstanding?.units?.shares ?? [];
  const shares = sh.reduce((best: any, f: any) => (!best || [f.end, f.filed ?? ""].join() > [best.end, best.filed ?? ""].join() ? f : best), null)?.val;
  return { name: json?.entityName ?? "", cik: json?.cik ?? 0, years: years.slice(-limit), sharesOutstanding: shares, lastFiled };
}

/** company_tickers.json → ticker → { cik, name, rank } (the file is ordered by market value). */
export function decodeTickers(json: any): Map<string, { cik: number; name: string; rank: number }> {
  const out = new Map<string, { cik: number; name: string; rank: number }>();
  for (const [k, r] of Object.entries<any>(json ?? {})) {
    const t = String(r.ticker).toUpperCase().replaceAll(".", "-");
    if (!out.has(t)) out.set(t, { cik: r.cik_str, name: r.title, rank: Number(k) });
  }
  return out;
}

// MARK: Filings (EVTS) and earnings dates

export interface Filing { form: string; date: number; title: string; url: string; isEarnings: boolean }
const ITEMS: Record<string, string> = { "1.01": "Material agreement", "1.03": "Bankruptcy", "2.01": "Acquisition / disposition", "2.02": "Earnings release",
  "2.05": "Restructuring costs", "2.06": "Impairment", "3.01": "Listing notice", "4.02": "Non-reliance on prior financials", "5.02": "Officer / director change",
  "5.03": "Bylaw amendment", "5.07": "Shareholder vote", "7.01": "Reg FD disclosure", "8.01": "Other material event" };
const FORMS: Record<string, string> = { "10-K": "Annual report", "10-Q": "Quarterly report", "DEF 14A": "Proxy statement", "S-1": "Registration",
  "SC 13D": "Activist stake (>5%)", "SC 13G": "Passive stake (>5%)", "4": "Insider transaction" };

export function decodeFilings(json: any, limit = 80): Filing[] {
  const r = json?.filings?.recent ?? {};
  const cik = Number(json?.cik ?? 0);
  const n = Math.min(...["accessionNumber", "filingDate", "form", "items", "primaryDocument"].map((k) => (r[k] ?? []).length));
  const out: Filing[] = [];
  for (let i = 0; i < n && out.length < limit; i++) {
    const form = r.form[i], date = day(r.filingDate[i]);
    if (!Number.isFinite(date)) continue;
    let title: string, earnings = false;
    if (form === "8-K") {
      const codes = String(r.items[i]).split(",").map((c) => c.trim());
      const named = codes.map((c) => ITEMS[c]).filter(Boolean);
      if (!named.length) continue;
      earnings = codes.includes("2.02"); title = named.join(" · ");
    } else if (FORMS[form]) title = FORMS[form]; else continue;
    const acc = String(r.accessionNumber[i]).replaceAll("-", "");
    const doc = String(r.primaryDocument[i]);
    if (!/^[\w.\-]+$/.test(doc) || !/^\d+$/.test(acc)) continue;
    out.push({ form, date, title, url: `https://www.sec.gov/Archives/edgar/data/${cik}/${acc}/${doc}`, isEarnings: earnings });
  }
  return out;
}

/** Every earnings release (8-K item 2.02), oldest first, extra filings within 45 days collapsed. */
export function earningsReleases(json: any): number[] {
  const r = json?.filings?.recent ?? {};
  const n = Math.min((r.form ?? []).length, (r.filingDate ?? []).length, (r.items ?? []).length);
  const raw: number[] = [];
  for (let i = 0; i < n; i++) if (r.form[i] === "8-K" && String(r.items[i]).split(",").some((c: string) => c.trim() === "2.02")) raw.push(day(r.filingDate[i]));
  raw.sort((a, b) => a - b);
  const out: number[] = [];
  for (const d of raw) if (!out.length || d - out[out.length - 1] >= 45 * 86_400_000) out.push(d);
  return out;
}

/** Next earnings from the company's own cadence: median gap between releases, ± median deviation. */
export function earningsEstimate(releases: number[], now = Date.now()) {
  if (!releases.length) return null;
  const recent = releases.slice(-9), last = releases[releases.length - 1];
  const gaps = recent.slice(1).map((d, i) => (d - recent[i]) / 86_400_000).filter((g) => g >= 60 && g <= 130);
  const median = (x: number[]) => { const s = [...x].sort((a, b) => a - b); return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2; };
  const cadence = gaps.length ? median(gaps) : 91;
  const spread = gaps.length >= 2 ? median(gaps.map((g) => Math.abs(g - cadence))) : null;
  let next = last + cadence * 86_400_000;
  while (next <= now) next += cadence * 86_400_000;
  const wd = new Date(next - 5 * 3_600_000).getUTCDay(); // New York weekday
  if (wd === 6) next -= 86_400_000; else if (wd === 0) next += 86_400_000;
  return { last, next, cadenceDays: cadence, spreadDays: spread, releases: releases.length };
}

// MARK: Screener frames (EQS)

export interface ScreenRow { cik: number; ticker: string; name: string; sizeRank: number; revenue?: number; netIncome?: number; assets?: number; liabilities?: number; equity?: number }
export const screenMetrics = (r: ScreenRow) => ({
  netMargin: r.revenue && r.revenue > 0 && r.netIncome != null ? r.netIncome / r.revenue : undefined,
  roe: r.equity && r.equity > 0 && r.netIncome != null ? r.netIncome / r.equity : undefined,
  roa: r.assets && r.assets > 0 && r.netIncome != null ? r.netIncome / r.assets : undefined,
  leverage: r.assets && r.assets > 0 && r.liabilities != null ? r.liabilities / r.assets : undefined,
});
export const decodeFrame = (json: any) => new Map<number, number>((json?.data ?? []).map((r: any) => [r.cik, r.val]));

/** Primary listing per CIK (lowest rank) from company_tickers.json. */
export function listings(json: any): Map<number, { ticker: string; name: string; rank: number }> {
  const out = new Map<number, { ticker: string; name: string; rank: number }>();
  for (const [k, r] of Object.entries<any>(json ?? {})) {
    const rank = Number(k), have = out.get(r.cik_str);
    if (have && have.rank <= rank) continue;
    out.set(r.cik_str, { ticker: String(r.ticker).toUpperCase().replaceAll(".", "-"), name: r.title, rank });
  }
  return out;
}

export function screenRows(l: Map<number, { ticker: string; name: string; rank: number }>, f: Record<string, Map<number, number>>): ScreenRow[] {
  const rows: ScreenRow[] = [];
  for (const [cik, x] of l) {
    const rev = f.revenues?.get(cik) ?? f.contract?.get(cik), ni = f.netIncome?.get(cik) ?? f.profitLoss?.get(cik), eq = f.equity?.get(cik) ?? f.equityNCI?.get(cik);
    let liab = f.liabilities?.get(cik);
    const total = f.liabEquity?.get(cik), e = f.equityNCI?.get(cik) ?? f.equity?.get(cik);
    if (liab == null && total != null && e != null) liab = total - e;
    if (rev == null && ni == null && f.assets?.get(cik) == null) continue;
    rows.push({ cik, ticker: x.ticker, name: x.name, sizeRank: x.rank, revenue: rev, netIncome: ni, assets: f.assets?.get(cik) ?? total, liabilities: liab, equity: eq });
  }
  return rows.sort((a, b) => a.sizeRank - b.sizeRank);
}
