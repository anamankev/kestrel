import { decodeDeribit, parseOption, DERIBIT_CURRENCIES, type OptionChain, type OptionContract } from "../core/options";
import { market } from "./market";

const cache = new Map<string, { at: number; chain: Promise<OptionChain> }>();

/** Deribit's public option book for BTC or ETH (no key; browsers may call it directly). Cached 10 s. */
export function optionChain(currency: string): Promise<OptionChain> {
  const hit = cache.get(currency);
  if (hit && Date.now() - hit.at < 10_000) return hit.chain;
  const chain = (async () => {
    const r = await fetch(`https://www.deribit.com/api/v2/public/get_book_summary_by_currency?currency=${encodeURIComponent(currency)}&kind=option`);
    if (!r.ok) throw new Error(`Deribit ${r.status}`);
    const c = decodeDeribit(await r.json());
    c.contracts.forEach(ingest);
    market.emit();
    return c;
  })();
  cache.set(currency, { at: Date.now(), chain });
  chain.catch(() => cache.delete(currency));
  return chain;
}

/** Publishes a contract's USD book as a quote, so tickets, the paper book and alerts can price it. */
export function ingest(c: OptionContract) {
  const last = c.mark ?? (c.bid != null && c.ask != null ? (c.bid + c.ask) / 2 : undefined);
  if (last == null) return;
  market.quotes.set(c.name, { last, bid: c.bid, ask: c.ask, time: Date.now() });
}

let timer = 0;
/** Keeps held or alerted options priced: refreshes their chains every 30 s. */
export function startOptionMarks() {
  if (timer) return;
  const tick = () => {
    const cur = new Set<string>();
    for (const f of market.held) for (const s of f()) { const p = parseOption(s); if (p && DERIBIT_CURRENCIES.has(p.underlying)) cur.add(p.underlying); }
    cur.forEach((c) => void optionChain(c).catch(() => {}));
  };
  tick();
  timer = window.setInterval(tick, 30_000);
}
