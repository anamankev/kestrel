export interface Quote {
  last: number;
  previousClose?: number;
  bid?: number;
  ask?: number;
  high?: number;
  low?: number;
  volume?: number;
  high52?: number;
  low52?: number;
  time: number; // ms epoch
}

export const change = (q?: Quote) => (q?.previousClose != null ? q.last - q.previousClose : undefined);
export const changePercent = (q?: Quote) => (q?.previousClose ? ((q.last - q.previousClose) / q.previousClose) * 100 : undefined);

export interface Candle { time: number; open: number; high: number; low: number; close: number; volume: number }

export interface TapePrint { id: string; price: number; size: number; side: "BUY" | "SELL"; time: number }
export interface BookLevel { price: number; size: number; cumulative: number }

/** A price-level aggregated limit order book maintained from snapshot + incremental updates. */
export class OrderBook {
  bids = new Map<number, number>();
  asks = new Map<number, number>();
  updated = 0;

  reset() { this.bids.clear(); this.asks.clear(); }
  apply(side: "bid" | "ask", price: number, size: number, time = Date.now()) {
    const m = side === "bid" ? this.bids : this.asks;
    if (size > 0) m.set(price, size); else m.delete(price);
    this.updated = time;
  }
  get bestBid() { let b: number | undefined; for (const p of this.bids.keys()) if (b === undefined || p > b) b = p; return b; }
  get bestAsk() { let a: number | undefined; for (const p of this.asks.keys()) if (a === undefined || p < a) a = p; return a; }
  get spread() { const b = this.bestBid, a = this.bestAsk; return b !== undefined && a !== undefined ? a - b : undefined; }

  /** The best `depth` levels per side, inside-out, with cumulative size. */
  ladder(depth: number): { bids: BookLevel[]; asks: BookLevel[] } {
    const top = (m: Map<number, number>, better: (a: number, b: number) => boolean) => {
      const best: [number, number][] = [];
      for (const [p, s] of m) {
        if (best.length === depth && !better(p, best[best.length - 1][0])) continue;
        let lo = 0, hi = best.length;
        while (lo < hi) { const mid = (lo + hi) >> 1; if (better(best[mid][0], p)) lo = mid + 1; else hi = mid; }
        best.splice(lo, 0, [p, s]);
        if (best.length > depth) best.pop();
      }
      let total = 0;
      return best.map(([price, size]) => { total += size; return { price, size, cumulative: total }; });
    };
    return { bids: top(this.bids, (a, b) => a > b), asks: top(this.asks, (a, b) => a < b) };
  }
}

export interface NewsItem { title: string; link: string; source: string; published: number; tickers: string[] }
