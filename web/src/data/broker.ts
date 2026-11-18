import { Store } from "./store";
import { market } from "./market";
import { PaperAccount, touchFrom, type Fill, type Order, type OrderType } from "../core/paper";
import type { TradeSide } from "../core/command";
import type { Instrument } from "../core/instrument";

export interface EquityPoint { t: number; v: number }

/** The signed-in user's paper book: live marking, fills and an equity curve, saved in the encrypted vault. */
export class PaperBroker extends Store {
  account = new PaperAccount();
  marks: Record<string, number> = {};
  curve: EquityPoint[] = [];
  lastFill: Fill | null = null;
  persist: () => void = () => {};
  private started = false;

  snapshot() { return { account: this.account, curve: this.curve.slice(-3000) }; }
  restore(raw: any) {
    this.account = PaperAccount.from(raw?.account);
    this.curve = (Array.isArray(raw?.curve) ? raw.curve : []).filter((p: any) => Number.isFinite(p?.t) && Number.isFinite(p?.v)).slice(-3000);
    this.marks = {}; this.lastFill = null;
    this.emit();
  }

  start() {
    if (this.started) return;
    this.started = true;
    market.subscribe(() => this.onMarket());
    market.held.push(() => this.relevant());
    window.setInterval(() => this.recordEquity(), 300_000);
  }

  /** Symbols the book needs priced. */
  private relevant() { return new Set([...this.account.openPositions.map((p) => p.symbol), ...this.account.workingOrders.map((o) => o.symbol)]); }

  private onMarket() {
    let filled = false, changed = false;
    for (const s of this.relevant()) {
      const t = touchFrom(market.quotes.get(s));
      if (!t) continue;
      if (this.marks[s] !== t.last) { this.marks[s] = t.last; changed = true; }
      const fills = this.account.mark(s, t);
      if (fills.length) { filled = true; this.lastFill = fills[fills.length - 1]; }
    }
    if (filled) { this.recordEquity(); this.persist(); }
    if (filled || changed) this.emit();
  }

  submit(i: Instrument, side: TradeSide, quantity: number, type: OrderType): Order {
    const q = market.quotes.get(i.symbol), t = touchFrom(q);
    const o = this.account.submit(i.symbol, side, quantity, type, t);
    if (t) this.marks[i.symbol] = t.last;
    if (o.status === "FILLED") this.lastFill = this.account.fills[this.account.fills.length - 1];
    this.recordEquity(); this.persist(); this.emit();
    return o;
  }
  cancel(id: number) { this.account.cancel(id); this.persist(); this.emit(); }
  reset() { this.account = new PaperAccount(); this.marks = {}; this.curve = []; this.lastFill = null; this.persist(); this.emit(); }

  recordEquity() {
    // Only meaningful once every open position has a live mark.
    if (!this.account.openPositions.every((p) => this.marks[p.symbol] != null)) return;
    const v = this.equity, last = this.curve[this.curve.length - 1];
    if (last && Math.abs(last.v - v) < 0.005 && Date.now() - last.t < 3_600_000) return;
    this.curve.push({ t: Date.now(), v });
    if (this.curve.length > 3000) this.curve.splice(0, this.curve.length - 3000);
    this.persist();
  }

  get equity() { return this.account.equity(this.marks); }
  get unrealized() { return this.account.openPositions.reduce((s, p) => s + (p.quantity * ((this.marks[p.symbol] ?? p.averageCost) - p.averageCost)), 0); }
  get totalPnL() { return this.equity - PaperAccount.startingCash; }
}

export const broker = new PaperBroker();
