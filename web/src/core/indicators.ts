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
