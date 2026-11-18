/** Crypto options: Black-76 pricing, Deribit chains and multi-leg strategies (ports of KestrelCore's Options and OptionStrategy). */
import type { Instrument } from "./instrument";

// MARK: Black-76 (options on forwards, r = 0 as on crypto venues)

export interface Greeks { price: number; delta: number; gamma: number; vega: number; theta: number }

/** Complementary error function: a Chebyshev fit (relative error < 1.2e-7) for |x| ≥ 0.5 and the Maclaurin series of erf below.
 *  erfc(−x) = 2 − erfc(x) holds exactly, so put-call parity holds to machine precision. */
function erfc(x: number): number {
  const z = Math.abs(x), t = 1 / (1 + 0.5 * z);
  let r = t * Math.exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
  if (z < 0.5) { // Maclaurin series for erf: exact to double precision here
    let term = z, sum = z;
    for (let n = 1; n < 30; n++) { term *= -z * z / n; sum += term / (2 * n + 1); }
    r = 1 - (2 / Math.sqrt(Math.PI)) * sum;
  }
  return x >= 0 ? r : 2 - r;
}
export const cdf = (x: number) => 0.5 * erfc(-x / Math.SQRT2);
const pdf = (x: number) => Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math.PI);

/** Forward `f`, strike `k`, years `t`, volatility `sigma` (0.5 = 50%). Vega is per vol point; theta per calendar day. */
export function greeks(f: number, k: number, t: number, sigma: number, call: boolean): Greeks {
  if (!(f > 0) || !(k > 0)) return { price: 0, delta: 0, gamma: 0, vega: 0, theta: 0 };
  if (!(t > 0) || !(sigma > 0)) {
    const itm = call ? f > k : f < k;
    return { price: Math.max(call ? f - k : k - f, 0), delta: itm ? (call ? 1 : -1) : 0, gamma: 0, vega: 0, theta: 0 };
  }
  const sd = sigma * Math.sqrt(t), d1 = (Math.log(f / k) + 0.5 * sigma * sigma * t) / sd, d2 = d1 - sd, n1 = pdf(d1);
  return {
    price: call ? f * cdf(d1) - k * cdf(d2) : k * cdf(-d2) - f * cdf(-d1),
    delta: call ? cdf(d1) : cdf(d1) - 1,
    gamma: n1 / (f * sd),
    vega: (f * n1 * Math.sqrt(t)) / 100,
    theta: (-f * n1 * sigma) / (2 * Math.sqrt(t)) / 365,
  };
}

/** Implied volatility by safeguarded Newton–bisection; undefined outside no-arbitrage bounds. */
export function impliedVol(price: number, f: number, k: number, t: number, call: boolean): number | undefined {
  const intrinsic = Math.max(call ? f - k : k - f, 0), cap = call ? f : k;
  if (!(t > 0) || !(price > intrinsic) || !(price < cap)) return undefined;
  let lo = 1e-4, hi = 10, sigma = 0.6;
  for (let i = 0; i < 100; i++) {
    const g = greeks(f, k, t, sigma, call), diff = g.price - price;
    if (Math.abs(diff) < 1e-10 * Math.max(price, 1)) return sigma;
    if (diff > 0) hi = sigma; else lo = sigma;
    const v = g.vega * 100, newton = v > 1e-12 ? sigma - diff / v : NaN;
    sigma = newton > lo && newton < hi ? newton : (lo + hi) / 2;
  }
  return sigma;
}

// MARK: Contracts and chains

export interface OptionContract {
  name: string; underlying: string; expiry: number; strike: number; isCall: boolean;
  /** USD prices (Deribit quotes in coin; converted with the expiry's forward). */
  bid?: number; ask?: number; mark?: number;
  /** Implied volatility as a fraction. */
  iv?: number; openInterest: number; volume: number; forward: number;
}
export const years = (c: OptionContract, now = Date.now()) => Math.max(c.expiry - now, 0) / (365 * 86_400_000);
export const contractGreeks = (c: OptionContract, now = Date.now()) => (c.iv == null ? undefined : greeks(c.forward, c.strike, years(c, now), c.iv, c.isCall));
export const isITM = (c: OptionContract) => (c.isCall ? c.forward > c.strike : c.forward < c.strike);

export interface StrikeRow { strike: number; call?: OptionContract; put?: OptionContract }

export class OptionChain {
  readonly expiries: number[];
  constructor(readonly contracts: OptionContract[]) { this.expiries = [...new Set(contracts.map((c) => c.expiry))].sort((a, b) => a - b); }
  at(e: number) { return this.contracts.filter((c) => c.expiry === e); }
  rows(e: number): StrikeRow[] {
    const m = new Map<number, StrikeRow>();
    for (const c of this.at(e)) { const r = m.get(c.strike) ?? { strike: c.strike }; if (c.isCall) r.call = c; else r.put = c; m.set(c.strike, r); }
    return [...m.values()].sort((a, b) => a.strike - b.strike);
  }
  forward(e: number) { return this.at(e)[0]?.forward; }
  atmStrike(e: number) {
    const f = this.forward(e);
    if (f == null) return undefined;
    return this.rows(e).reduce<StrikeRow | undefined>((b, r) => (!b || Math.abs(r.strike - f) < Math.abs(b.strike - f) ? r : b), undefined)?.strike;
  }
  atmIV(e: number) {
    const k = this.atmStrike(e), row = this.rows(e).find((r) => r.strike === k);
    const ivs = [row?.call?.iv, row?.put?.iv].filter((v): v is number => v != null);
    return ivs.length ? ivs.reduce((a, b) => a + b, 0) / ivs.length : undefined;
  }
  /** Settlement price that minimises the total payout to option holders. */
  maxPain(e: number) {
    const cs = this.at(e), pay = (s: number) => cs.reduce((a, c) => a + c.openInterest * Math.max(c.isCall ? s - c.strike : c.strike - s, 0), 0);
    return [...new Set(cs.map((c) => c.strike))].sort((a, b) => a - b).reduce<number | undefined>((b, s) => (b == null || pay(s) < pay(b) ? s : b), undefined);
  }
  putCallOI(e?: number) {
    const cs = e == null ? this.contracts : this.at(e);
    const calls = cs.filter((c) => c.isCall).reduce((a, c) => a + c.openInterest, 0), puts = cs.filter((c) => !c.isCall).reduce((a, c) => a + c.openInterest, 0);
    return calls > 0 ? puts / calls : undefined;
  }
}

// MARK: Deribit

export const DERIBIT_CURRENCIES = new Set(["BTC", "ETH"]);
const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

/** Parses `BTC-20NOV26-64000-P`. Deribit options expire at 08:00 UTC. */
export function parseOption(name: string): { underlying: string; expiry: number; strike: number; call: boolean } | undefined {
  const m = /^([A-Z]{2,6})-(\d{1,2})([A-Z]{3})(\d{2})-(\d+(?:d\d+)?)-([CP])$/.exec(name);
  if (!m) return undefined;
  const mon = MONTHS.indexOf(m[3]), day = Number(m[2]), strike = Number(m[5].replace("d", "."));
  if (mon < 0 || day < 1 || day > 31 || !(strike > 0)) return undefined;
  return { underlying: m[1], expiry: Date.UTC(2000 + Number(m[4]), mon, day, 8), strike, call: m[6] === "C" };
}

/** An option as a tradable instrument (symbol = Deribit name). */
export function optionInstrument(name: string): Instrument | undefined {
  const p = parseOption(name);
  if (!p) return undefined;
  const d = new Date(p.expiry);
  const label = `${p.underlying} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${String(d.getUTCFullYear()).slice(2)} ${p.strike.toLocaleString("en-US")} ${p.call ? "CALL" : "PUT"}`;
  return { symbol: name, ticker: name, name: label, assetClass: "OPTION" };
}

export function decodeDeribit(json: any): OptionChain {
  const rows: any[] = Array.isArray(json?.result) ? json.result : [];
  const out: OptionContract[] = [];
  for (const r of rows) {
    const p = typeof r?.instrument_name === "string" ? parseOption(r.instrument_name) : undefined, fwd = Number(r?.underlying_price);
    if (!p || !(fwd > 0)) continue;
    const usd = (v: any) => (Number(v) > 0 ? Number(v) * fwd : undefined);
    out.push({ name: r.instrument_name, underlying: p.underlying, expiry: p.expiry, strike: p.strike, isCall: p.call, bid: usd(r.bid_price), ask: usd(r.ask_price), mark: usd(r.mark_price),
      iv: Number(r.mark_iv) > 0 ? Number(r.mark_iv) / 100 : undefined, openInterest: Number(r.open_interest) || 0, volume: Number(r.volume) || 0, forward: fwd });
  }
  return new OptionChain(out);
}

// MARK: Strategies

export interface Leg { contract: OptionContract; quantity: number }
export const TEMPLATES = ["LONG CALL", "LONG PUT", "STRADDLE", "STRANGLE", "BULL CALL SPREAD", "BEAR PUT SPREAD", "IRON CONDOR", "CALL BUTTERFLY"] as const;
export type Template = (typeof TEMPLATES)[number];

/** Builds the legs from listed strikes nearest to fixed distances from the forward; undefined when strikes collapse. */
export function templateLegs(t: Template, chain: OptionChain, e: number): Leg[] | undefined {
  const rows = chain.rows(e).filter((r) => r.call?.mark != null && r.put?.mark != null), f = chain.forward(e);
  if (f == null || rows.length < 3) return undefined;
  const row = (m: number) => rows.reduce((b, r) => (Math.abs(r.strike - f * m) < Math.abs(b.strike - f * m) ? r : b));
  const C = (m: number, q: number): Leg => ({ contract: row(m).call!, quantity: q }), P = (m: number, q: number): Leg => ({ contract: row(m).put!, quantity: q });
  const legs: Leg[] = {
    "LONG CALL": [C(1, 1)], "LONG PUT": [P(1, 1)], STRADDLE: [C(1, 1), P(1, 1)], STRANGLE: [P(0.93, 1), C(1.07, 1)],
    "BULL CALL SPREAD": [C(1, 1), C(1.08, -1)], "BEAR PUT SPREAD": [P(1, 1), P(0.92, -1)],
    "IRON CONDOR": [P(0.88, 1), P(0.94, -1), C(1.06, -1), C(1.12, 1)], "CALL BUTTERFLY": [C(0.94, 1), C(1, -2), C(1.06, 1)],
  }[t];
  return new Set(legs.map((l) => l.contract.name)).size === legs.length ? legs : undefined;
}

const intrinsic = (l: Leg, s: number) => Math.max(l.contract.isCall ? s - l.contract.strike : l.contract.strike - s, 0);

export class StrategyAnalysis {
  constructor(readonly legs: Leg[]) {}
  /** Positive = debit paid, negative = credit received. */
  get netPremium() { return this.legs.reduce((a, l) => a + l.quantity * (l.contract.mark ?? 0), 0); }
  payoffAtExpiry(s: number) { return this.legs.reduce((a, l) => a + l.quantity * intrinsic(l, s), 0) - this.netPremium; }
  /** Model P&L if the forward moved to `s` now, holding each leg's implied vol. */
  valueToday(s: number, now = Date.now()) {
    return this.legs.reduce((a, l) => a + l.quantity * greeks(s, l.contract.strike, years(l.contract, now), l.contract.iv ?? 0, l.contract.isCall).price, 0) - this.netPremium;
  }
  greeks(now = Date.now()): Greeks {
    const g: Greeks = { price: 0, delta: 0, gamma: 0, vega: 0, theta: 0 };
    for (const l of this.legs) { const x = contractGreeks(l.contract, now); if (x) for (const k of Object.keys(g) as (keyof Greeks)[]) g[k] += l.quantity * x[k]; }
    return g;
  }
  private get strikes() { return [...new Set(this.legs.map((l) => l.contract.strike))].sort((a, b) => a - b); }
  private get upperSlope() { return this.legs.filter((l) => l.contract.isCall).reduce((a, l) => a + l.quantity, 0); }
  private get knots() { const s = this.strikes; return s.length ? [0, ...s, s[s.length - 1] * 2] : []; }
  /** undefined = unlimited. */
  get maxProfit() { return this.upperSlope > 1e-9 ? undefined : Math.max(...this.knots.map((k) => this.payoffAtExpiry(k))); }
  get maxLoss() { return this.upperSlope < -1e-9 ? undefined : Math.min(0, ...this.knots.map((k) => this.payoffAtExpiry(k))); }
  get breakevens(): number[] {
    const k = this.knots, out: number[] = [];
    for (let i = 0; i + 1 < k.length; i++) {
      const a = k[i], b = k[i + 1], pa = this.payoffAtExpiry(a), pb = this.payoffAtExpiry(b);
      if (pa === 0) out.push(a);
      if (pa < 0 !== pb < 0 && pa !== 0 && pb !== 0) out.push(a + ((b - a) * pa) / (pa - pb));
    }
    const last = k[k.length - 1], up = this.upperSlope;
    if (last != null && Math.abs(up) > 1e-9) { const p = this.payoffAtExpiry(last); if (p < 0 === up > 0) out.push(last - p / up); }
    return [...new Set(out.map((v) => Math.round(v * 100) / 100))].sort((a, b) => a - b);
  }
}
