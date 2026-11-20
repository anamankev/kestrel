/** GC and YAS: U.S. Treasury par yield curves and fixed-coupon bond math. Mirrors KestrelCore/Bonds.swift. */

/** Tenors shown in GC, as Treasury labels them in the CSV header, with their length in years. */
export const TENORS: { label: string; header: string; years: number }[] = [
  { label: "1M", header: "1 Mo", years: 1 / 12 }, { label: "2M", header: "2 Mo", years: 2 / 12 }, { label: "3M", header: "3 Mo", years: 0.25 },
  { label: "4M", header: "4 Mo", years: 4 / 12 }, { label: "6M", header: "6 Mo", years: 0.5 }, { label: "1Y", header: "1 Yr", years: 1 },
  { label: "2Y", header: "2 Yr", years: 2 }, { label: "3Y", header: "3 Yr", years: 3 }, { label: "5Y", header: "5 Yr", years: 5 },
  { label: "7Y", header: "7 Yr", years: 7 }, { label: "10Y", header: "10 Yr", years: 10 }, { label: "20Y", header: "20 Yr", years: 20 },
  { label: "30Y", header: "30 Yr", years: 30 },
];

/** One day's par yields in percent, by tenor label; a tenor Treasury didn't publish that day is missing. */
export interface CurveDay { date: number; yields: Record<string, number> }

/** Treasury's daily par yield curve CSV (one file per year), oldest day first. */
export function parseTreasuryCSV(text: string): CurveDay[] {
  const lines = text.trim().split(/\r?\n/);
  if (lines.length < 2) return [];
  const head = lines[0].split(",").map((h) => h.replace(/"/g, "").trim());
  const cols = TENORS.map((t) => ({ label: t.label, at: head.indexOf(t.header) })).filter((c) => c.at > 0);
  const out: CurveDay[] = [];
  for (const line of lines.slice(1)) {
    const f = line.split(",");
    const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(f[0]?.trim() ?? "");
    if (!m) continue;
    const yields: Record<string, number> = {};
    for (const c of cols) { const v = Number(f[c.at]); if (f[c.at]?.trim() && Number.isFinite(v)) yields[c.label] = v; }
    if (Object.keys(yields).length) out.push({ date: Date.UTC(+m[3], +m[1] - 1, +m[2]), yields });
  }
  return out.sort((a, b) => a.date - b.date);
}

/** The last curve published on or before `date` (rows sorted oldest first). */
export function curveOn(days: CurveDay[], date: number): CurveDay | undefined {
  let lo = 0, hi = days.length - 1, best: CurveDay | undefined;
  while (lo <= hi) { const m = (lo + hi) >> 1; if (days[m].date <= date) { best = days[m]; lo = m + 1; } else hi = m - 1; }
  return best;
}

/** Par yield at any maturity by straight-line interpolation between published tenors (flat beyond the ends). */
export function interpolate(day: CurveDay, years: number): number | undefined {
  const pts = TENORS.filter((t) => day.yields[t.label] != null).map((t) => [t.years, day.yields[t.label]] as const);
  if (!pts.length) return undefined;
  if (years <= pts[0][0]) return pts[0][1];
  for (let k = 1; k < pts.length; k++) {
    const [x0, y0] = pts[k - 1], [x1, y1] = pts[k];
    if (years <= x1) return y0 + ((y1 - y0) * (years - x0)) / (x1 - x0);
  }
  return pts[pts.length - 1][1];
}

// MARK: Bond math (per 100 face, yields and coupons as decimals)

export interface BondRisk { clean: number; dirty: number; accrued: number; macaulay: number; modified: number; convexity: number; dv01: number }

/** Where settlement sits in the coupon schedule: `n` coupons left, the next one `w` of a period away
 *  (actual/actual: days to the next coupon over days in the period). `years` is the time to maturity. */
export interface Schedule { n: number; w: number; years: number }

const DAY_MS = 86_400_000;
function addMonths(t: number, months: number, day: number): number {
  const d = new Date(t), y = d.getUTCFullYear(), m = d.getUTCMonth() + months;
  const last = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  return Date.UTC(y, m, Math.min(day, last));
}

/** Coupon schedule from settlement to maturity (UTC midnights), stepping back from maturity like a real bond. */
export function schedule(settle: number, maturity: number, freq = 2): Schedule | undefined {
  if (!(maturity > settle)) return undefined;
  const step = 12 / freq, day = new Date(maturity).getUTCDate();
  let next = maturity, n = 1;
  for (;;) {
    const prev = addMonths(maturity, -step * n, day);
    if (prev <= settle) return { n, w: (next - settle) / (next - prev), years: (maturity - settle) / (365.25 * DAY_MS) };
    next = prev; n++;
    if (n > 1200) return undefined;
  }
}

/** Price and risk per 100 face at a yield (decimal). Street convention: compounding at the coupon frequency,
 *  accrued interest for the elapsed part of the current coupon period. */
export function bondRisk(coupon: number, s: Pick<Schedule, "n" | "w">, yld: number, freq = 2): BondRisk {
  const cpn = (100 * coupon) / freq, d = 1 + yld / freq;
  let dirty = 0, dur = 0, cvx = 0;
  for (let k = 0; k < s.n; k++) {
    const p = k + s.w, t = p / freq, cf = cpn + (k === s.n - 1 ? 100 : 0), pv = cf / d ** p;
    dirty += pv; dur += t * pv; cvx += t * (t + 1 / freq) * pv;
  }
  const accrued = cpn * (1 - s.w);
  const macaulay = dur / dirty, modified = macaulay / d;
  return { clean: dirty - accrued, dirty, accrued, macaulay, modified, convexity: cvx / (dirty * d * d), dv01: (modified * dirty) / 10_000 };
}

/** Yield to maturity for a clean price (bisection; prices fall as yields rise). */
export function yieldFromPrice(coupon: number, s: Pick<Schedule, "n" | "w">, clean: number, freq = 2): number | undefined {
  if (!(clean > 0) || !(s.n > 0)) return undefined;
  let lo = -0.05, hi = 1;
  if (bondRisk(coupon, s, lo, freq).clean < clean || bondRisk(coupon, s, hi, freq).clean > clean) return undefined;
  for (let k = 0; k < 200 && hi - lo > 1e-12; k++) {
    const mid = (lo + hi) / 2;
    if (bondRisk(coupon, s, mid, freq).clean > clean) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}
