import type { Candle, Quote } from "./market";
import type { Instrument } from "./instrument";
import { exchangeSuffixes, instrument as known, token } from "./universe";

export interface ChartSeries { name?: string; exchange?: string; currency?: string; quote: Quote; candles: Candle[]; dividends: { date: number; amount: number }[] }

/** Yahoo v8 chart JSON. `adjusted` scales each bar by adjclose/close (total return). */
export function decodeChart(json: any, intraday = true, adjusted = false): ChartSeries {
  const r = json?.chart?.result?.[0];
  if (!r) throw new Error("No result");
  const m = r.meta ?? {};
  const q = r.indicators?.quote?.[0] ?? {};
  const adj: (number | null)[] | undefined = adjusted ? r.indicators?.adjclose?.[0]?.adjclose : undefined;
  const candles: Candle[] = [];
  (r.timestamp ?? []).forEach((t: number, i: number) => {
    const o = q.open?.[i], h = q.high?.[i], l = q.low?.[i], c = q.close?.[i];
    if (o == null || h == null || l == null || c == null) return;
    const a = adj?.[i];
    const k = a != null && c > 0 && a > 0 ? a / c : 1;
    candles.push({ time: t * 1000, open: o * k, high: h * k, low: l * k, close: c * k, volume: q.volume?.[i] ?? 0 });
  });
  const last = m.regularMarketPrice ?? candles[candles.length - 1]?.close;
  if (last == null) throw new Error("No price");
  const pos = (v?: number) => (v && v > 0 ? v : undefined);
  const dividends = Object.values(r.events?.dividends ?? {})
    .map((d: any) => ({ date: d.date * 1000, amount: d.amount })).filter((d) => d.amount > 0).sort((a, b) => a.date - b.date);
  return {
    name: m.longName ?? m.shortName, exchange: m.fullExchangeName, currency: m.currency, candles, dividends,
    quote: {
      last, previousClose: intraday ? (m.previousClose ?? m.chartPreviousClose) : m.chartPreviousClose,
      high: pos(m.regularMarketDayHigh), low: pos(m.regularMarketDayLow), volume: pos(m.regularMarketVolume),
      high52: m.fiftyTwoWeekHigh, low52: m.fiftyTwoWeekLow, time: (m.regularMarketTime ?? Date.now() / 1000) * 1000,
    },
  };
}

export interface SearchHit { instrument: Instrument; exchange: string; kind: string; token: string }

/** Yahoo search JSON → hits mapped onto Kestrel asset classes (options and unknown types skipped). */
export function decodeSearch(json: any): SearchHit[] {
  const seen = new Set<string>();
  const out: SearchHit[] = [];
  for (const q of json?.quotes ?? []) {
    const s = String(q.symbol ?? "").toUpperCase();
    if (!s || s.length > 24) continue;
    const name = String(q.longname ?? q.shortname ?? s).trim();
    const i = mapType(s, name, q.quoteType ?? "");
    if (!i || seen.has(i.symbol)) continue;
    seen.add(i.symbol);
    out.push({ instrument: i, exchange: q.exchDisp ?? "", kind: q.typeDisp ?? q.quoteType ?? "", token: token(i) });
  }
  return out;
}

function mapType(s: string, name: string, type: string): Instrument | undefined {
  switch (type) {
    case "EQUITY": case "ETF": case "MUTUALFUND": {
      const suffix = s.includes(".") ? s.split(".").pop()! : "";
      return { symbol: s, ticker: s, name, assetClass: "EQUITY", region: exchangeSuffixes[suffix] ?? "AMERICAS" };
    }
    case "INDEX": return known(s) ?? { symbol: s, ticker: s, name, assetClass: "INDEX" };
    case "CURRENCY": {
      const pair = s.endsWith("=X") ? s.slice(0, -2) : s;
      if (pair.length !== 6) return undefined;
      return known(`${pair}=X`) ?? { symbol: `${pair}=X`, ticker: pair, name, assetClass: "CURNCY" };
    }
    case "FUTURE": return known(s) ?? { symbol: s, ticker: s, name, assetClass: "CMDTY" };
    case "CRYPTOCURRENCY": {
      const k = known(s);
      if (k) return k;
      return s.endsWith("-USD") ? { symbol: s, ticker: s, name, assetClass: "CRYPTO" } : undefined;
    }
  }
  return undefined;
}

/** Yahoo v8 spark (batch): symbol → latest quote and intraday closes. */
export function decodeSpark(json: any, now = Date.now()): Map<string, { quote: Quote; closes: number[] }> {
  const out = new Map<string, { quote: Quote; closes: number[] }>();
  for (const [sym, v] of Object.entries<any>(json ?? {})) {
    const closes: number[] = (v?.close ?? []).filter((x: unknown): x is number => typeof x === "number" && Number.isFinite(x));
    const last = closes[closes.length - 1] ?? v?.fulldayPrice;
    if (typeof last !== "number") continue;
    const ts: number[] = v?.timestamp ?? [];
    out.set(sym.toUpperCase(), {
      closes,
      quote: { last, previousClose: v?.previousClose ?? v?.chartPreviousClose, high: closes.length ? Math.max(...closes) : undefined,
        low: closes.length ? Math.min(...closes) : undefined, time: ts.length ? ts[ts.length - 1] * 1000 : now },
    });
  }
  return out;
}
