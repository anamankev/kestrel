/** RV: relative valuation against same-industry peers (SEC SIC code), from SEC annual data and delayed prices. */
import type { ScreenRow } from "./sec";

/** Companies in an EDGAR company-list Atom feed (`browse-edgar … output=atom`), one per `<entry>`.
 *  A company with former names has an escaped `<formerly-names>` block between its CIK and name. */
export function decodeSicFeed(xml: string): { cik: number; name: string }[] {
  const out: { cik: number; name: string }[] = [];
  for (const entry of xml.split("<entry>").slice(1)) {
    const cik = /<cik>(\d{1,10})<\/cik>/.exec(entry), name = /<name>([^<]{1,200})<\/name>/.exec(entry);
    if (cik && name) out.push({ cik: Number(cik[1]), name: name[1].replace(/&amp;/g, "&").trim() });
  }
  return out;
}

/** Up to `n` peers with annual data, closest in revenue to the target (log scale). */
export function pickPeers(target: ScreenRow, rows: ScreenRow[], members: Set<number>, n = 12): ScreenRow[] {
  const t = target.revenue && target.revenue > 0 ? Math.log(target.revenue) : null;
  const dist = (r: ScreenRow) => (t != null && r.revenue && r.revenue > 0 ? Math.abs(Math.log(r.revenue) - t) : Infinity);
  return rows.filter((r) => r.cik !== target.cik && members.has(r.cik)).sort((a, b) => dist(a) - dist(b) || a.sizeRank - b.sizeRank).slice(0, n);
}

export interface RVRow {
  cik: number; ticker: string; name: string; isTarget: boolean;
  price?: number; marketCap?: number; pe?: number; ps?: number; pb?: number;
  revenue?: number; growth?: number; margin?: number; roe?: number; leverage?: number;
}

const ok = (v: number | undefined): v is number => v != null && Number.isFinite(v);
const ratio = (a?: number, b?: number) => (ok(a) && ok(b) && b > 0 ? a / b : undefined);

/** Valuation and quality ratios for one company. P/E is left blank when earnings are negative. */
export function rvRow(r: ScreenRow, isTarget: boolean, price?: number, shares?: number, priorRevenue?: number): RVRow {
  const marketCap = ok(price) && ok(shares) && shares > 0 ? price * shares : undefined;
  return {
    cik: r.cik, ticker: r.ticker, name: r.name, isTarget, price, marketCap,
    pe: r.netIncome != null && r.netIncome > 0 ? ratio(marketCap, r.netIncome) : undefined,
    ps: ratio(marketCap, r.revenue), pb: ratio(marketCap, r.equity),
    revenue: r.revenue,
    growth: ok(r.revenue) && ok(priorRevenue) && priorRevenue > 0 ? r.revenue / priorRevenue - 1 : undefined,
    margin: ok(r.netIncome) ? ratio(r.netIncome, r.revenue) : undefined,
    roe: ok(r.netIncome) ? ratio(r.netIncome, r.equity) : undefined,
    leverage: ratio(r.liabilities, r.assets),
  };
}

/** Median of the defined values (peer benchmark), or undefined. */
export function median(values: (number | undefined)[]): number | undefined {
  const v = values.filter(ok).sort((a, b) => a - b);
  if (!v.length) return undefined;
  const m = v.length >> 1;
  return v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2;
}

/** Where the target sits against peers: its value over the peer median, minus one. */
export const premium = (value?: number, peerMedian?: number) => (ok(value) && ok(peerMedian) && peerMedian > 0 ? value / peerMedian - 1 : undefined);
