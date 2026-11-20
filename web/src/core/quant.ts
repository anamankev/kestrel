/** The app's research maths (Risk, Research, Backtest, EventStudy, History .swift), ported line for line. */
import type { Candle } from "./market";
import { bollinger, rsi, sma } from "./indicators";

const sum = (x: number[]) => x.reduce((a, b) => a + b, 0);
const mean = (x: number[]) => sum(x) / x.length;
const sdSample = (x: number[]) => { const m = mean(x); return Math.sqrt(x.reduce((a, v) => a + (v - m) ** 2, 0) / Math.max(x.length - 1, 1)); };

// MARK: Risk

export const returns = (closes: number[]) => closes.slice(1).map((c, i) => (closes[i] > 0 ? c / closes[i] - 1 : NaN)).filter(Number.isFinite);

/** UTC calendar day of a timestamp (ms). */
export const utcDay = (t: number) => Math.floor(t / 86_400_000) * 86_400_000;
/** yyyymmdd (UTC), the Fama-French files' key. */
export const yyyymmdd = (t: number) => { const d = new Date(t); return d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate(); };

/** Closes on the UTC dates every series shares, oldest first. */
export function alignedCloses(series: Record<string, Candle[]>): { dates: number[]; closes: Record<string, number[]> } {
  const maps = Object.fromEntries(Object.entries(series).map(([k, cs]) => [k, new Map(cs.map((c) => [utcDay(c.time), c.close]))]));
  const keys = Object.keys(maps);
  if (!keys.length) return { dates: [], closes: {} };
  const dates = [...maps[keys[0]].keys()].filter((d) => keys.every((k) => maps[k].has(d))).sort((a, b) => a - b);
  return { dates, closes: Object.fromEntries(keys.map((k) => [k, dates.map((d) => maps[k].get(d)!)])) };
}
export const alignedReturns = (series: Record<string, Candle[]>) =>
  Object.fromEntries(Object.entries(alignedCloses(series).closes).map(([k, v]) => [k, returns(v)]));

export function correlation(x: number[], y: number[]): number | null {
  const n = Math.min(x.length, y.length);
  if (n < 20) return null;
  const a = x.slice(-n), b = y.slice(-n), ma = mean(a), mb = mean(b);
  let cov = 0, va = 0, vb = 0;
  for (let i = 0; i < n; i++) { cov += (a[i] - ma) * (b[i] - mb); va += (a[i] - ma) ** 2; vb += (b[i] - mb) ** 2; }
  if (va <= 1e-20 || vb <= 1e-20) return null;
  return Math.min(Math.max(cov / Math.sqrt(va * vb), -1), 1);
}
export const correlationMatrix = (r: Record<string, number[]>, symbols: string[]) =>
  symbols.map((a) => symbols.map((b) => (!r[a] || !r[b] ? null : a === b ? (r[a].length >= 20 ? 1 : null) : correlation(r[a], r[b]))));

// MARK: Regression (BETA)

export interface Regression { alpha: number; beta: number; alphaSE: number; betaSE: number; r2: number; correlation: number; residualSD: number; n: number }
export const tStat = (v: number, se: number) => (se > 0 ? v / se : NaN);
export const adjustedBeta = (b: number) => 0.67 * b + 0.33;

export function ols(yIn: number[], xIn: number[]): Regression | null {
  const n = Math.min(xIn.length, yIn.length);
  if (n < 3) return null;
  const x = xIn.slice(-n), y = yIn.slice(-n), mx = mean(x), my = mean(y);
  let sxx = 0, sxy = 0, syy = 0;
  for (let i = 0; i < n; i++) { const dx = x[i] - mx, dy = y[i] - my; sxx += dx * dx; sxy += dx * dy; syy += dy * dy; }
  if (sxx <= 1e-20) return null;
  const beta = sxy / sxx, alpha = my - beta * mx;
  let sse = 0;
  for (let i = 0; i < n; i++) sse += (y[i] - alpha - beta * x[i]) ** 2;
  const s2 = sse / (n - 2);
  return { alpha, beta, alphaSE: Math.sqrt(s2 * (1 / n + (mx * mx) / sxx)), betaSE: Math.sqrt(s2 / sxx),
    r2: syy > 0 ? Math.max(0, 1 - sse / syy) : 0, correlation: syy > 0 ? sxy / Math.sqrt(sxx * syy) : 0, residualSD: Math.sqrt(s2), n };
}

// MARK: Performance (COMP)

export interface Performance { totalReturn: number; annualizedReturn: number; annualizedVol: number; sharpe: number | null; maxDrawdown: number }
export function performance(closes: number[], periodsPerYear: number, riskFree = 0): Performance | null {
  if (closes.length < 3 || !(closes[0] > 0)) return null;
  const r = returns(closes), years = r.length / periodsPerYear, total = closes[closes.length - 1] / closes[0] - 1;
  const ann = years > 0 ? (1 + total) ** (1 / years) - 1 : 0;
  const vol = sdSample(r) * Math.sqrt(periodsPerYear);
  let peak = closes[0], dd = 0;
  for (const c of closes) { peak = Math.max(peak, c); dd = Math.min(dd, c / peak - 1); }
  return { totalReturn: total, annualizedReturn: ann, annualizedVol: vol, sharpe: vol > 0 ? (ann - riskFree) / vol : null, maxDrawdown: dd };
}
export const rebased = (c: number[]) => (c[0] > 0 ? c.map((v) => (v / c[0]) * 100) : []);

// MARK: Efficient frontier (MVO)

export interface Portfolio { weights: number[]; expectedReturn: number; volatility: number }
export const sharpeOf = (p: Portfolio, rf: number) => (p.volatility > 0 ? (p.expectedReturn - rf) / p.volatility : 0);

export function moments(r: number[][], periodsPerYear: number): { mu: number[]; cov: number[][] } | null {
  const k = r.length, n = Math.min(...r.map((x) => x.length));
  if (k < 2 || n < 20) return null;
  const s = r.map((x) => x.slice(-n)), m = s.map(mean);
  const cov = s.map(() => new Array(k).fill(0));
  for (let i = 0; i < k; i++) for (let j = i; j < k; j++) {
    let c = 0;
    for (let t = 0; t < n; t++) c += (s[i][t] - m[i]) * (s[j][t] - m[j]);
    cov[i][j] = cov[j][i] = (c / (n - 1)) * periodsPerYear;
  }
  return { mu: m.map((v) => v * periodsPerYear), cov };
}

export function projectToSimplex(v: number[]): number[] {
  const u = [...v].sort((a, b) => b - a);
  let css = 0, theta = 0;
  u.forEach((x, i) => { css += x; const t = (css - 1) / (i + 1); if (x - t > 0) theta = t; });
  return v.map((x) => Math.max(x - theta, 0));
}

function evaluate(w: number[], mu: number[], cov: number[][]): Portfolio {
  let variance = 0;
  for (let i = 0; i < w.length; i++) for (let j = 0; j < w.length; j++) variance += w[i] * w[j] * cov[i][j];
  return { weights: w, expectedReturn: w.reduce((a, x, i) => a + x * mu[i], 0), volatility: Math.sqrt(Math.max(variance, 0)) };
}

/** Minimizes wᵀΣw − λ·μᵀw over long-only, fully invested weights (projected gradient). */
export function optimize(mu: number[], cov: number[][], lambda: number, iterations = 3000): Portfolio {
  const k = mu.length;
  const lip = 2 * Math.max(...cov.map((r) => sum(r.map(Math.abs))));
  const step = 1 / Math.max(lip, 1e-12);
  let w = new Array(k).fill(1 / k);
  for (let it = 0; it < iterations; it++) {
    const g = mu.map((_, i) => 2 * cov[i].reduce((a, c, j) => a + c * w[j], 0) - lambda * mu[i]);
    const next = projectToSimplex(w.map((x, i) => x - step * g[i]));
    const moved = Math.max(...next.map((x, i) => Math.abs(x - w[i])));
    w = next;
    if (moved < 1e-10) break;
  }
  return evaluate(w, mu, cov);
}

export function frontier(mu: number[], cov: number[][], riskFree: number, points = 40) {
  if (mu.length < 2 || cov.length !== mu.length) return null;
  const minVariance = optimize(mu, cov, 0);
  const curve = [minVariance];
  const scale = Math.max(...cov.map((r) => Math.max(...r.map(Math.abs)))) / Math.max(Math.max(...mu.map(Math.abs)), 1e-9);
  for (let p = 1; p <= points; p++) curve.push(optimize(mu, cov, scale * 0.01 * 1000 ** (p / points)));
  const out: Portfolio[] = [];
  for (const p of curve.sort((a, b) => a.volatility - b.volatility)) if (!out.length || p.expectedReturn > out[out.length - 1].expectedReturn + 1e-9) out.push(p);
  const maxSharpe = out.reduce((b, p) => (sharpeOf(p, riskFree) > sharpeOf(b, riskFree) ? p : b), out[0] ?? minVariance);
  return { frontier: out, minVariance, maxSharpe };
}

// MARK: Multiple regression (FACT)

export interface Term { name: string; coefficient: number; standardError: number }
export interface LinearFit { terms: Term[]; r2: number; adjustedR2: number; residualSD: number; n: number }

function invert(m: number[][]): number[][] | null {
  const n = m.length;
  const a = m.map((row, i) => [...row, ...Array.from({ length: n }, (_, j) => (i === j ? 1 : 0))]);
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(a[r][c]) > Math.abs(a[p][c])) p = r;
    if (Math.abs(a[p][c]) <= 1e-14) return null;
    [a[c], a[p]] = [a[p], a[c]];
    const d = a[c][c];
    for (let j = 0; j < 2 * n; j++) a[c][j] /= d;
    for (let r = 0; r < n; r++) if (r !== c) { const f = a[r][c]; if (f) for (let j = 0; j < 2 * n; j++) a[r][j] -= f * a[c][j]; }
  }
  return a.map((row) => row.slice(n));
}

/** OLS with intercept: y = a + Σ bᵢ·xᵢ + e. */
export function linearFit(y: number[], columns: number[][], names: string[]): LinearFit | null {
  const n = y.length, k = columns.length + 1;
  if (n <= k + 1 || !columns.every((c) => c.length === n) || names.length !== columns.length) return null;
  const x = (r: number, j: number) => (j === 0 ? 1 : columns[j - 1][r]);
  const xtx = Array.from({ length: k }, () => new Array(k).fill(0)), xty = new Array(k).fill(0);
  for (let r = 0; r < n; r++) for (let i = 0; i < k; i++) { const xi = x(r, i); xty[i] += xi * y[r]; for (let j = i; j < k; j++) xtx[i][j] += xi * x(r, j); }
  for (let i = 0; i < k; i++) for (let j = 0; j < i; j++) xtx[i][j] = xtx[j][i];
  const inv = invert(xtx);
  if (!inv) return null;
  const beta = inv.map((row) => row.reduce((a, v, j) => a + v * xty[j], 0));
  const my = mean(y);
  let sse = 0, sst = 0;
  for (let r = 0; r < n; r++) { const f = beta.reduce((a, b, j) => a + b * x(r, j), 0); sse += (y[r] - f) ** 2; sst += (y[r] - my) ** 2; }
  const s2 = sse / (n - k), r2 = sst > 0 ? Math.max(0, 1 - sse / sst) : 0;
  return { terms: beta.map((b, i) => ({ name: i === 0 ? "Alpha" : names[i - 1], coefficient: b, standardError: Math.sqrt(Math.max(inv[i][i], 0) * s2) })),
    r2, adjustedR2: 1 - ((1 - r2) * (n - 1)) / (n - k), residualSD: Math.sqrt(s2), n };
}

// MARK: Dividends (DVD)

export interface Dividend { date: number; amount: number }
export function dividendSummary(divs: Dividend[], price?: number, now = Date.now()) {
  if (!divs.length) return null;
  const ttm = sum(divs.filter((d) => d.date > now - 365 * 86_400_000 && d.date <= now).map((d) => d.amount));
  const thisYear = new Date(now).getUTCFullYear();
  const by = new Map<number, Dividend[]>();
  for (const d of divs) { const y = new Date(d.date).getUTCFullYear(); by.set(y, [...(by.get(y) ?? []), d]); }
  const annual = [...by].map(([year, l]) => ({ year, total: sum(l.map((d) => d.amount)), count: l.length })).sort((a, b) => a.year - b.year);
  const complete = annual.filter((a) => a.year < thisYear);
  const counts = complete.slice(-3).map((a) => a.count);
  const freq = counts.length ? counts.reduce((best, c) => (counts.filter((x) => x === c).length > counts.filter((x) => x === best).length ? c : best), counts[0]) : 0;
  let growth: number | null = null;
  if (complete.length >= 6) { const last = complete[complete.length - 1], first = complete[complete.length - 6]; if (last.total > 0 && first.total > 0) growth = (last.total / first.total) ** (1 / 5) - 1; }
  return { trailing12M: ttm, yield: price && price > 0 ? ttm / price : null, paymentsPerYear: freq, annual, growth5Y: growth };
}

// MARK: Event study (EVST)

export interface StudyEvent { day0: number; abnormal: number[]; alpha: number; beta: number; estimationDays: number }
export interface EventStudy { window: [number, number]; events: StudyEvent[]; pending: StudyEvent[]; aar: number[]; caar: number[]; caarSE: number[] }

export const car = (s: EventStudy, e: StudyEvent, from: number, to: number) => {
  const lo = Math.max(from, s.window[0]) - s.window[0], hi = Math.min(Math.min(to, s.window[1]) - s.window[0], e.abnormal.length - 1);
  return lo <= hi ? sum(e.abnormal.slice(lo, hi + 1)) : 0;
};
export const lastDay = (s: EventStudy, e: StudyEvent) => s.window[0] + e.abnormal.length - 1;
export function carSummary(s: EventStudy, from: number, to: number) {
  const cars = s.events.map((e) => car(s, e, from, to)), n = cars.length, m = n ? mean(cars) : 0;
  let t: number | null = null;
  if (n >= 2) { const sd = Math.sqrt(cars.reduce((a, c) => a + (c - m) ** 2, 0) / (n - 1)); if (sd > 0) t = m / (sd / Math.sqrt(n)); }
  return { mean: m, t, positive: n ? cars.filter((c) => c > 0).length / n : 0 };
}

/** Market-model event study (MacKinlay 1997); other events' windows are left out of each estimation. */
export function eventStudy(asset: Candle[], market: Candle[], dates: number[], window: [number, number] = [-5, 5], estimation = 250, gap = 10, minimum = 120): EventStudy | null {
  const al = alignedCloses({ a: asset, m: market });
  const ca = al.closes.a, cm = al.closes.m;
  if (!ca || ca.length <= 2) return null;
  const ra = ca.slice(1).map((c, i) => c / ca[i] - 1), rm = cm.slice(1).map((c, i) => c / cm[i] - 1), rd = al.dates.slice(1);
  const zero: number[] = [];
  for (const d of [...dates].sort((a, b) => a - b)) {
    const key = yyyymmdd(d), k = rd.findIndex((x) => yyyymmdd(x) >= key);
    if (k >= 0 && !zero.includes(k)) zero.push(k);
  }
  const bad = new Set<number>();
  for (const k of zero) for (let d = window[0]; d <= window[1]; d++) bad.add(k + d);
  const events: StudyEvent[] = [], pending: StudyEvent[] = [];
  const width = window[1] - window[0] + 1;
  for (const k of zero) {
    const first = k + window[0], last = Math.min(k + window[1], ra.length - 1);
    if (first < 0) continue;
    const idx: number[] = [];
    for (let i = first - gap - 1; i >= 0 && idx.length < estimation; i--) if (!bad.has(i)) idx.push(i);
    const fit = idx.length >= minimum ? ols(idx.map((i) => ra[i]), idx.map((i) => rm[i])) : null;
    if (!fit) continue;
    const ar: number[] = [];
    for (let i = first; i <= last; i++) ar.push(ra[i] - (fit.alpha + fit.beta * rm[i]));
    const e = { day0: rd[k], abnormal: ar, alpha: fit.alpha, beta: fit.beta, estimationDays: idx.length };
    (ar.length === width ? events : pending).push(e);
  }
  if (!events.length && !pending.length) return null;
  if (!events.length) return { window, events, pending, aar: [], caar: [], caarSE: [] };
  const n = events.length, aar = Array.from({ length: width }, (_, d) => mean(events.map((e) => e.abnormal[d])));
  const caar: number[] = [], se: number[] = [];
  let run = 0;
  for (let d = 0; d < width; d++) {
    run += aar[d]; caar.push(run);
    const cars = events.map((e) => sum(e.abnormal.slice(0, d + 1)));
    se.push(n >= 2 ? Math.sqrt(cars.reduce((a, c) => a + (c - run) ** 2, 0) / (n - 1)) / Math.sqrt(n) : 0);
  }
  return { window, events, pending, aar, caar, caarSE: se };
}

// MARK: Backtest (BT)

export type Strategy = { kind: "sma"; fast: number; slow: number } | { kind: "rsi"; period: number; buyBelow: number; sellAbove: number } | { kind: "bollinger"; period: number; k: number } | { kind: "hold" };
export const strategyLabel = (s: Strategy) => s.kind === "sma" ? `SMA ${s.fast}/${s.slow} cross` : s.kind === "rsi" ? `RSI(${s.period}) buy < ${s.buyBelow}, sell > ${s.sellAbove}` : s.kind === "bollinger" ? `Bollinger(${s.period}, ${s.k}) mean reversion` : "Buy and hold";

function targets(s: Strategy, closes: number[]): (boolean | null)[] {
  if (s.kind === "hold") return closes.map(() => true);
  if (s.kind === "sma") { const a = sma(closes, s.fast), b = sma(closes, s.slow); return closes.map((_, i) => (a[i] == null || b[i] == null ? null : a[i]! > b[i]!)); }
  if (s.kind === "rsi") { let st = false; return rsi(closes, s.period).map((v) => { if (v == null) return null; if (v < s.buyBelow) st = true; else if (v > s.sellAbove) st = false; return st; }); }
  const bands = bollinger(closes, s.period, s.k);
  let st = false;
  return closes.map((c, i) => { const b = bands[i]; if (!b) return null; if (c < b.lower) st = true; else if (c >= b.mid) st = false; return st; });
}

export interface BacktestTrade { entry: number; exit: number | null; entryPrice: number; exitPrice: number; returnPct: number }
export interface BacktestResult { dates: number[]; equity: number[]; benchmark: number[]; trades: BacktestTrade[]; totalReturn: number; benchmarkReturn: number; cagr: number | null; sharpe: number | null; maxDrawdown: number; exposure: number; volatility: number | null; sortino: number | null; riskFree: number }

/** No look-ahead: signals at the close act at the next open; idle cash earns the risk-free rate. */
export function backtest(bars: Candle[], s: Strategy, costBps = 5, periodsPerYear = 252, riskFree?: number[]): BacktestResult | null {
  if (bars.length < 3) return null;
  const closes = bars.map((b) => b.close), target = targets(s, closes), cost = costBps / 10_000;
  const rf = (t: number) => ((riskFree?.length ? riskFree[Math.min(t, riskFree.length - 1)] : 0) ?? 0) / periodsPerYear;
  const equity = [1], bench = [1], day: number[] = [], excess: number[] = [], trades: BacktestTrade[] = [];
  let held = false, daysIn = 0, open: { date: number; price: number; equity: number } | null = null;
  for (let t = 1; t < bars.length; t++) {
    const want: boolean = target[t - 1] ?? held; const prev = closes[t - 1], o = bars[t].open > 0 ? bars[t].open : prev, c = closes[t];
    let r: number;
    if (!held && want) { r = c / o - 1 - cost; open = { date: bars[t].time, price: o, equity: equity[equity.length - 1] }; }
    else if (held && !want) r = o / prev - 1 - cost;
    else if (held && want) r = c / prev - 1;
    else r = rf(t);
    if (held && !want && open) { const after = equity[equity.length - 1] * (1 + r); trades.push({ entry: open.date, exit: bars[t].time, entryPrice: open.price, exitPrice: o, returnPct: after / open.equity - 1 }); open = null; }
    held = want; if (held) daysIn++;
    equity.push(equity[equity.length - 1] * (1 + r)); bench.push(c / closes[0]); day.push(r); excess.push(r - rf(t));
  }
  if (open) trades.push({ entry: open.date, exit: null, entryPrice: open.price, exitPrice: closes[closes.length - 1], returnPct: equity[equity.length - 1] / open.equity - 1 });
  const years = (bars[bars.length - 1].time - bars[0].time) / (365.25 * 86_400_000);
  const m = mean(excess), sd = sdSample(excess), down = Math.sqrt(excess.reduce((a, x) => a + Math.min(x, 0) ** 2, 0) / excess.length), raw = sdSample(day);
  let peak = 1, mdd = 0;
  for (const v of equity) { peak = Math.max(peak, v); mdd = Math.max(mdd, 1 - v / peak); }
  const last = equity[equity.length - 1];
  return { dates: bars.map((b) => b.time), equity, benchmark: bench, trades, totalReturn: last - 1, benchmarkReturn: closes[closes.length - 1] / closes[0] - 1,
    cagr: years >= 0.25 ? last ** (1 / years) - 1 : null, sharpe: sd > 0 ? (m / sd) * Math.sqrt(periodsPerYear) : null, maxDrawdown: mdd,
    exposure: daysIn / (bars.length - 1), volatility: raw > 0 ? raw * Math.sqrt(periodsPerYear) : null, sortino: down > 0 ? (m / down) * Math.sqrt(periodsPerYear) : null,
    riskFree: riskFree?.length ? mean(riskFree) : 0 };
}
export const calmar = (r: BacktestResult) => (r.cagr != null && r.maxDrawdown > 0 ? r.cagr / r.maxDrawdown : null);
export const winRate = (r: BacktestResult) => { const c = r.trades.filter((t) => t.exit != null); return c.length ? c.filter((t) => t.returnPct > 0).length / c.length : null; };

// MARK: History stats (HP)

export function returnStats(closesIn: number[], periodsPerYear: number) {
  const c = closesIn.filter((x) => x > 0 && Number.isFinite(x));
  if (c.length < 3) return null;
  const simple = c.slice(1).map((v, i) => v / c[i] - 1), logs = c.slice(1).map((v, i) => Math.log(v / c[i]));
  const m = mean(logs), variance = logs.reduce((a, v) => a + (v - m) ** 2, 0) / (logs.length - 1);
  let peak = c[0], mdd = 0;
  for (const p of c) { peak = Math.max(peak, p); mdd = Math.min(mdd, p / peak - 1); }
  return { totalReturn: c[c.length - 1] / c[0] - 1, annualizedVolatility: Math.sqrt(variance * periodsPerYear), maxDrawdown: mdd, best: Math.max(...simple), worst: Math.min(...simple), periods: simple.length };
}

// MARK: CSV

/** RFC 4180; text starting with = + - @ is prefixed with ' so spreadsheets never run it as a formula. */
export function csvField(s: string): string {
  let v = s;
  if (/^[=+\-@]/.test(v) && !Number.isFinite(Number(v))) v = "'" + v;
  return /[",\n\r]/.test(v) ? `"${v.replaceAll('"', '""')}"` : v;
}
export const csv = (header: string[], rows: string[][]) => [header, ...rows].map((r) => r.map(csvField).join(",")).join("\r\n") + "\r\n";
export const csvNum = (v: number | null | undefined, digits = 6) => (v == null || !Number.isFinite(v) ? "" : v.toFixed(digits));

/** Parses RFC 4180 CSV (quoted fields may hold commas, quotes and newlines) into rows of fields. */
export function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], f = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; continue; }
    if (c === '"') q = true;
    else if (c === ",") { row.push(f); f = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(f); rows.push(row); row = []; f = ""; }
    else f += c;
  }
  if (f || row.length) { row.push(f); rows.push(row); }
  return rows;
}
/** Tab-separated text for the clipboard: pastes into Excel or Numbers cells and reads with pandas.read_clipboard().
 *  Tabs and line breaks inside fields become spaces so every cell stays in place. */
export const toTSV = (csvText: string) => parseCSV(csvText).map((r) => r.map((f) => f.replace(/[\t\r\n]+/g, " ")).join("\t")).join("\n") + "\n";

// MARK: Portfolio risk (KestrelCore Risk)

/** OLS beta of date-aligned asset returns on market returns (cov / var); null under 20 observations. */
export function betaOf(asset: number[], market: number[]): number | null {
  const n = Math.min(asset.length, market.length);
  if (n < 20) return null;
  const a = asset.slice(-n), m = market.slice(-n), ma = a.reduce((s, v) => s + v, 0) / n, mm = m.reduce((s, v) => s + v, 0) / n;
  let cov = 0, vm = 0;
  for (let i = 0; i < n; i++) { cov += (a[i] - ma) * (m[i] - mm); vm += (m[i] - mm) ** 2; }
  return vm > 0 ? cov / vm : null;
}
/** One-day historical-simulation VaR as a positive loss (0 if the tail shows no loss). */
export function historicalVaR(pnl: number[], confidence = 0.95): number | null {
  if (pnl.length < 20 || confidence < 0.5 || confidence >= 1) return null;
  const s = [...pnl].sort((a, b) => a - b);
  return Math.max(-s[Math.min(Math.floor(s.length * (1 - confidence)), s.length - 1)], 0);
}
/** Expected shortfall: mean loss on the days beyond VaR. */
export function expectedShortfall(pnl: number[], confidence = 0.95): number | null {
  if (pnl.length < 20) return null;
  const s = [...pnl].sort((a, b) => a - b), k = Math.max(Math.floor(s.length * (1 - confidence)), 1);
  return Math.max(-s.slice(0, k).reduce((a, b) => a + b, 0) / k, 0);
}
/** Daily P&L history of a portfolio holding `exposure` (signed market value per symbol). */
export function pnlSeries(exposure: Record<string, number>, rets: Record<string, number[]>): number[] {
  const lens = Object.keys(exposure).map((k) => rets[k]?.length).filter((v): v is number => v != null);
  const n = lens.length ? Math.min(...lens) : 0;
  return Array.from({ length: n }, (_, t) => Object.entries(exposure).reduce((a, [k, v]) => { const r = rets[k]; return a + (r ? v * r[r.length - n + t] : 0); }, 0));
}

// MARK: Seasonality (SEAS)

export interface MonthReturn { year: number; month: number; ret: number }
export interface MonthStat { month: number; mean?: number; median?: number; positive?: number; best?: number; worst?: number; n: number }

/** Calendar-month returns from monthly (or finer) bars: the last close of each month over the previous month's.
 *  The current, unfinished month is left out. */
export function monthlyReturns(bars: Candle[], now = Date.now()): MonthReturn[] {
  const ends = new Map<number, number>();   // year*12+month -> last close
  for (const b of [...bars].sort((a, c) => a.time - c.time)) {
    if (!(b.close > 0)) continue;
    const d = new Date(b.time); ends.set(d.getUTCFullYear() * 12 + d.getUTCMonth(), b.close);
  }
  const n = new Date(now), current = n.getUTCFullYear() * 12 + n.getUTCMonth();
  const out: MonthReturn[] = [];
  for (const [k, close] of ends) {
    const prev = ends.get(k - 1);
    if (prev && k < current) out.push({ year: Math.floor(k / 12), month: k % 12, ret: close / prev - 1 });
  }
  return out.sort((a, b) => a.year - b.year || a.month - b.month);
}

/** Average, median, share positive, best and worst return for each calendar month (0 = January). */
export function seasonality(rets: MonthReturn[]): MonthStat[] {
  return Array.from({ length: 12 }, (_, month) => {
    const v = rets.filter((r) => r.month === month).map((r) => r.ret).sort((a, b) => a - b);
    if (!v.length) return { month, n: 0 };
    const m = v.length >> 1;
    return { month, n: v.length, mean: v.reduce((a, b) => a + b, 0) / v.length, median: v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2,
      positive: v.filter((x) => x > 0).length / v.length, best: v[v.length - 1], worst: v[0] };
  });
}
