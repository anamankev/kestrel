import type { Candle } from "./market";

/** Technical studies. Outputs align index-for-index with the input; warm-up slots are null. */
export function sma(x: number[], n: number): (number | null)[] {
  const out: (number | null)[] = x.map(() => null);
  if (n <= 0) return out;
  let sum = 0;
  x.forEach((v, i) => { sum += v; if (i >= n) sum -= x[i - n]; if (i >= n - 1) out[i] = sum / n; });
  return out;
}

export interface Band { mid: number; upper: number; lower: number }
/** Bollinger bands (population standard deviation). */
export function bollinger(x: number[], n = 20, k = 2): (Band | null)[] {
  const mid = sma(x, n);
  return x.map((_, i) => {
    const m = mid[i];
    if (m === null) return null;
    let s = 0;
    for (let j = i - n + 1; j <= i; j++) s += (x[j] - m) ** 2;
    const sd = Math.sqrt(s / n);
    return { mid: m, upper: m + k * sd, lower: m - k * sd };
  });
}

/** Wilder's RSI. */
export function rsi(x: number[], n = 14): (number | null)[] {
  const out: (number | null)[] = x.map(() => null);
  if (x.length <= n) return out;
  let gain = 0, loss = 0;
  for (let i = 1; i <= n; i++) { const d = x[i] - x[i - 1]; if (d > 0) gain += d; else loss -= d; }
  gain /= n; loss /= n;
  const value = () => (loss === 0 ? 100 : 100 - 100 / (1 + gain / loss));
  out[n] = value();
  for (let i = n + 1; i < x.length; i++) {
    const d = x[i] - x[i - 1];
    gain = (gain * (n - 1) + Math.max(d, 0)) / n;
    loss = (loss * (n - 1) + Math.max(-d, 0)) / n;
    out[i] = value();
  }
  return out;
}

/** Session VWAP using typical price. */
export function vwap(c: Candle[]): (number | null)[] {
  let pv = 0, vol = 0;
  return c.map((k) => { pv += ((k.high + k.low + k.close) / 3) * k.volume; vol += k.volume; return vol > 0 ? pv / vol : null; });
}

/** Rebases a chart and a comparison series to % change from their first shared bar (KestrelCore `Indicators.rebase`).
 *  The comparison takes, at each main bar, its last close at or before that time. */
export function rebase(main: Candle[], other: Candle[]): { main: Candle[]; other: (number | null)[] } {
  const base = main[0]?.close;
  if (!(base > 0)) return { main, other: [] };
  const pct = (v: number) => (v / base - 1) * 100;
  const m = main.map((k) => ({ ...k, open: pct(k.open), high: pct(k.high), low: pct(k.low), close: pct(k.close) }));
  const sorted = [...other].sort((a, b) => a.time - b.time);
  const closeAt = (t: number) => {
    let lo = 0, hi = sorted.length - 1, best = -1;
    while (lo <= hi) { const mid = (lo + hi) >> 1; if (sorted[mid].time <= t) { best = mid; lo = mid + 1; } else hi = mid - 1; }
    return best >= 0 ? sorted[best].close : null;
  };
  const raw = main.map((k) => closeAt(k.time));
  const cBase = raw.find((v): v is number => v != null);
  if (!(cBase && cBase > 0)) return { main: m, other: [] };
  return { main: m, other: raw.map((v) => (v == null ? null : (v / cBase - 1) * 100)) };
}
