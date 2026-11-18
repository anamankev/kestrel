import { Store } from "./store";
import type { Quote, TapePrint } from "../core/market";
import { OrderBook } from "../core/market";
import type { Instrument } from "../core/instrument";
import { crypto, all, isStreaming, instrument, resolve } from "../core/universe";
import { decode, feedURL, subscribe } from "../core/coinbase";
import { chart, spark } from "./relay";

/** Live crypto from Coinbase's public WebSocket plus delayed Yahoo quotes through the relay. */
export class MarketStore extends Store {
  quotes = new Map<string, Quote>();
  details = new Map<string, { name?: string; exchange?: string; currency?: string }>();
  sparks = new Map<string, number[]>();
  books = new Map<string, OrderBook>();
  tapes = new Map<string, TapePrint[]>();
  unknown = new Set<string>();
  live = false;
  messagesPerSecond = 0;
  /** Symbols on screen: refreshed often. Everything in the universe refreshes slowly. */
  focus = new Set<string>();
  private count = 0;
  private timers: number[] = [];

  start() {
    if (this.timers.length) return;
    this.connect();
    this.timers.push(window.setInterval(() => { this.messagesPerSecond = this.count; this.count = 0; this.emit(); }, 1000));
    void this.refresh(all.filter((i) => !isStreaming(i)));
    this.timers.push(window.setInterval(() => void this.refresh(all.filter((i) => !isStreaming(i))), 45_000));
    this.timers.push(window.setInterval(() => void this.detail(this.focused()), 15_000));
    void this.loadSparks();
  }

  private focused(): Instrument[] {
    return [...this.focus].map((s) => instrument(s) ?? resolve(s)).filter((i): i is Instrument => !!i && !isStreaming(i) && i.assetClass !== "OPTION");
  }

  private connect() {
    const ws = new WebSocket(feedURL);
    const products = crypto.map((c) => c.symbol);
    ws.onopen = () => {
      for (const ch of ["heartbeats", "ticker", "level2", "market_trades"]) ws.send(subscribe(ch, products));
      this.live = true; this.emit();
    };
    ws.onmessage = (e) => {
      this.count++;
      let msg: unknown;
      try { msg = JSON.parse(e.data as string); } catch { return; }
      for (const ev of decode(msg)) {
        if (ev.kind === "ticker") {
          this.quotes.set(ev.product, ev.quote);
          const s = this.sparks.get(ev.product);
          if (s?.length) s[s.length - 1] = ev.quote.last;
        } else if (ev.kind === "book") {
          let b = this.books.get(ev.product);
          if (!b) { b = new OrderBook(); this.books.set(ev.product, b); }
          if (ev.snapshot) b.reset();
          for (const u of ev.updates) b.apply(u.side, u.price, u.size);
        } else {
          const t = [...ev.prints, ...(this.tapes.get(ev.product) ?? [])].slice(0, 200);
          this.tapes.set(ev.product, t);
        }
      }
      this.emit();
    };
    ws.onclose = () => { this.live = false; this.emit(); window.setTimeout(() => this.connect(), 3000); };
    ws.onerror = () => ws.close();
  }

  /** Delayed quotes and intraday sparklines: batches of 20 symbols, three requests at a time. */
  async refresh(list: Instrument[]) {
    const symbols = [...new Set(list.map((i) => i.symbol))];
    const batches: string[][] = [];
    for (let k = 0; k < symbols.length; k += 20) batches.push(symbols.slice(k, k + 20));
    const worker = async () => {
      for (let b = batches.shift(); b; b = batches.shift()) {
        try {
          const got = await spark(b);
          for (const s of b) {
            const v = got.get(s);
            if (!v) { this.unknown.add(s); continue; }
            const prev = this.quotes.get(s);
            // Keep the richer fields (volume, 52-week range) a detail fetch already supplied.
            this.quotes.set(s, { ...prev, ...v.quote, volume: prev?.volume, high52: prev?.high52, low52: prev?.low52 });
            if (v.closes.length) this.sparks.set(s, v.closes);
            this.unknown.delete(s);
          }
        } catch { /* retried on the next cycle */ }
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    this.emit();
  }

  /** Full detail (name, exchange, volume, day and 52-week range) for securities open in a panel. */
  async detail(list: Instrument[]) {
    await Promise.all(list.slice(0, 6).map(async (i) => {
      try {
        const s = await chart(i.symbol, "1d", "5m");
        this.quotes.set(i.symbol, s.quote);
        this.details.set(i.symbol, { name: s.name, exchange: s.exchange, currency: s.currency });
        if (s.candles.length) this.sparks.set(i.symbol, s.candles.map((c) => c.close));
        this.unknown.delete(i.symbol);
      } catch (e) {
        if (String(e).includes("404")) this.unknown.add(i.symbol);
      }
    }));
    this.emit();
  }

  private async loadSparks() {
    await Promise.all(crypto.map(async (c) => {
      try {
        const r = await fetch(`https://api.exchange.coinbase.com/products/${c.symbol}/candles?granularity=900`);
        const rows = (await r.json()) as number[][];
        if (Array.isArray(rows)) this.sparks.set(c.symbol, rows.slice(0, 96).reverse().map((k) => k[4]));
      } catch { /* sparklines are optional */ }
    }));
    this.emit();
  }

  /** Fetch now for a security just loaded into a panel. */
  touch(i: Instrument) {
    if (!isStreaming(i) && i.assetClass !== "OPTION" && !this.details.has(i.symbol)) void this.detail([i]);
  }

  displayName(i: Instrument) {
    return i.name !== i.ticker && i.name !== i.symbol ? i.name : this.details.get(i.symbol)?.name ?? i.name;
  }
}

export const market = new MarketStore();
