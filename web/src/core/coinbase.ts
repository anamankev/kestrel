import type { Quote, TapePrint } from "./market";

export const feedURL = "wss://advanced-trade-ws.coinbase.com";
export const subscribe = (channel: string, products: string[]) => JSON.stringify({ type: "subscribe", product_ids: products, channel });

export type CoinbaseEvent =
  | { kind: "ticker"; product: string; quote: Quote }
  | { kind: "book"; product: string; snapshot: boolean; updates: { side: "bid" | "ask"; price: number; size: number }[] }
  | { kind: "trades"; product: string; prints: TapePrint[] };

const num = (s?: string) => (s == null ? undefined : Number.isFinite(Number(s)) ? Number(s) : undefined);

/** Decodes one Coinbase Advanced Trade WebSocket message (public market-data channels). */
export function decode(msg: any, now = Date.now()): CoinbaseEvent[] {
  const events: any[] = msg?.events ?? [];
  switch (msg?.channel) {
    case "ticker":
      return events.flatMap((e) => e.tickers ?? []).flatMap((t: any) => {
        const last = num(t.price);
        if (last === undefined) return [];
        const pct = num(t.price_percent_chg_24_h);
        return [{ kind: "ticker" as const, product: t.product_id, quote: {
          last, previousClose: pct !== undefined ? last / (1 + pct / 100) : undefined, bid: num(t.best_bid), ask: num(t.best_ask),
          high: num(t.high_24_h), low: num(t.low_24_h), volume: num(t.volume_24_h), high52: num(t.high_52_w), low52: num(t.low_52_w), time: now } }];
      });
    case "l2_data":
      return events.filter((e) => e.product_id).map((e) => ({
        kind: "book" as const, product: e.product_id, snapshot: e.type === "snapshot",
        updates: (e.updates ?? []).flatMap((l: any) => {
          const p = num(l.price_level), q = num(l.new_quantity);
          return p === undefined || q === undefined ? [] : [{ side: l.side === "bid" ? "bid" as const : "ask" as const, price: p, size: q }];
        }),
      }));
    case "market_trades": {
      const grouped = new Map<string, TapePrint[]>();
      for (const t of events.flatMap((e) => e.trades ?? [])) {
        const px = num(t.price), sz = num(t.size);
        if (px === undefined || sz === undefined) continue;
        // Coinbase reports the maker side; the aggressor (what the tape shows) is the opposite.
        const p: TapePrint = { id: t.trade_id, price: px, size: sz, side: t.side === "SELL" ? "BUY" : "SELL", time: Date.parse(t.time) || now };
        grouped.set(t.product_id, [...(grouped.get(t.product_id) ?? []), p]);
      }
      return [...grouped].map(([product, prints]) => ({ kind: "trades" as const, product, prints: prints.sort((a, b) => b.time - a.time) }));
    }
  }
  return [];
}
