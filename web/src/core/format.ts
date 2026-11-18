import type { AssetClass } from "./instrument";

/** Decimal places appropriate to the instrument and price magnitude. */
export function places(v: number, cls?: AssetClass): number {
  if (cls === "CURNCY") return v > 20 ? 3 : 4;
  if (cls === "GOVT") return 3;
  const a = Math.abs(v);
  return a >= 1 ? 2 : a >= 0.01 ? 4 : 6;
}

const nf = (d: number, group = true) => new Intl.NumberFormat("en-US", { minimumFractionDigits: d, maximumFractionDigits: d, useGrouping: group });

export const price = (v?: number, cls?: AssetClass) => (v == null || !Number.isFinite(v) ? "—" : nf(places(v, cls)).format(v));
/** Formats `v` with the precision of a reference price (a change next to its last). */
export const priceLike = (v?: number, ref?: number, cls?: AssetClass) => (v == null || !Number.isFinite(v) ? "—" : nf(places(ref ?? v, cls)).format(v));
export const signed = (v?: number, ref?: number, cls?: AssetClass) => (v == null || !Number.isFinite(v) ? "—" : (v > 0 ? "+" : "") + priceLike(v, ref, cls));
export const pct = (v?: number) => (v == null || !Number.isFinite(v) ? "—" : (v > 0 ? "+" : "") + nf(2).format(v) + "%");

export function compact(v?: number): string {
  if (v == null || !Number.isFinite(v)) return "—";
  const a = Math.abs(v);
  const [d, s] = a >= 1e12 ? [1e12, "T"] : a >= 1e9 ? [1e9, "B"] : a >= 1e6 ? [1e6, "M"] : a >= 1e3 ? [1e3, "K"] : [1, ""];
  return nf(s ? 2 : 0).format(v / d) + s;
}

export const money = (v: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(v);

/** 24-hour HH:mm:ss in a time zone (never 12-hour without AM/PM). */
export const clock = (t: number | Date, timeZone?: string) =>
  new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false, timeZone }).format(t);
