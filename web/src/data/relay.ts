import { sourceOfPath } from "../core/health";
import { health } from "./health";
import { decodeChart, decodeSearch, decodeSpark, type ChartSeries, type SearchHit } from "../core/yahoo";

/** The Cloudflare relay (see worker/). Local `npm run relay` serves it on :8787. */
export const RELAY = (import.meta.env.VITE_RELAY_URL as string | undefined) ?? "http://localhost:8787";

export async function relayFetch(path: string, signal?: AbortSignal): Promise<Response> {
  const id = sourceOfPath(path), t = performance.now();
  try {
    const r = await fetch(`${RELAY}${path}`, { signal });
    if (!r.ok) throw new Error(`relay ${r.status}`);
    if (id) health.record(id, true, performance.now() - t);
    return r;
  } catch (e) {
    // A request the app cancelled (screen closed) says nothing about the source.
    if (id && !(e instanceof DOMException && e.name === "AbortError")) health.record(id, false, performance.now() - t, e instanceof Error ? e.message : "failed");
    throw e;
  }
}

export async function chart(symbol: string, range: string, interval: string, opts: { adjusted?: boolean; intraday?: boolean; signal?: AbortSignal } = {}): Promise<ChartSeries> {
  const q = new URLSearchParams({ range, interval });
  if (opts.adjusted) q.set("events", "div,splits");
  const r = await relayFetch(`/yahoo/chart/${encodeURIComponent(symbol)}?${q}`, opts.signal);
  return decodeChart(await r.json(), opts.intraday ?? true, opts.adjusted ?? false);
}

export async function searchSecurities(query: string, n = 10, signal?: AbortSignal): Promise<SearchHit[]> {
  const q = query.trim();
  if (q.length < 1 || q.length > 64) return [];
  const r = await relayFetch(`/yahoo/search?${new URLSearchParams({ q, n: String(n) })}`, signal);
  return decodeSearch(await r.json());
}

/** Batch quotes for up to 20 symbols per request. */
export async function spark(symbols: string[], signal?: AbortSignal) {
  const r = await relayFetch(`/yahoo/spark?${new URLSearchParams({ symbols: symbols.join(","), range: "1d", interval: "5m" })}`, signal);
  return decodeSpark(await r.json());
}
