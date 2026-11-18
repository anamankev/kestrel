import type { NewsItem } from "../core/market";
import { relayFetch } from "./relay";

export const SOURCES: [string, string][] = [["cnbc", "CNBC"], ["cnbcfin", "CNBC FIN"], ["marketwatch", "MKTWATCH"], ["coindesk", "COINDESK"]];

/** Parses RSS 2.0; only https links with a host are kept (no javascript: or data: URLs). */
export function parseRSS(xml: string, source: string): NewsItem[] {
  const doc = new DOMParser().parseFromString(xml, "text/xml");
  return [...doc.querySelectorAll("item")].flatMap((it) => {
    const title = it.querySelector("title")?.textContent?.trim() ?? "";
    const link = it.querySelector("link")?.textContent?.trim() ?? "";
    let ok = false;
    try { const u = new URL(link); ok = u.protocol === "https:" && !!u.host; } catch { ok = false; }
    if (!title || !ok) return [];
    const published = Date.parse(it.querySelector("pubDate")?.textContent ?? "") || 0;
    return [{ title, link, source, published, tickers: [] }];
  });
}

export async function topNews(signal?: AbortSignal): Promise<NewsItem[]> {
  const all = await Promise.allSettled(SOURCES.map(async ([id, label]) => parseRSS(await (await relayFetch(`/rss/${id}`, signal)).text(), label)));
  const seen = new Set<string>();
  return all.flatMap((r) => (r.status === "fulfilled" ? r.value : []))
    .filter((n) => !seen.has(n.title) && seen.add(n.title)).sort((a, b) => b.published - a.published);
}

export async function companyNews(symbol: string, signal?: AbortSignal): Promise<NewsItem[]> {
  const r = await relayFetch(`/rss/company?s=${encodeURIComponent(symbol)}`, signal);
  return parseRSS(await r.text(), "YAHOO").sort((a, b) => b.published - a.published);
}

/** TOP search: words must all appear; "exact phrases" in quotes; -word excludes. */
export function matches(item: NewsItem, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  const title = item.title.toLowerCase();
  const phrases = [...q.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  const rest = q.replace(/"[^"]*"/g, " ").split(/\s+/).filter(Boolean);
  return phrases.every((p) => title.includes(p))
    && rest.filter((w) => !w.startsWith("-")).every((w) => title.includes(w))
    && rest.filter((w) => w.startsWith("-") && w.length > 1).every((w) => !title.includes(w.slice(1)));
}
