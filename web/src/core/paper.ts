/** Simulated execution, ported from KestrelCore's PaperAccount. Amounts are rounded to 8 places after every step so cash never drifts. */
import type { TradeSide } from "./command";
import { parseOption } from "./options";

export type OrderType =
  | { kind: "market" }
  | { kind: "limit"; limit: number }
  /** Becomes a market order once the last trade reaches the stop (buy: at or above, sell: at or below). */
  | { kind: "stop"; stop: number }
  /** Becomes a limit order at `limit` once the last trade reaches `stop`. */
  | { kind: "stopLimit"; stop: number; limit: number };
export type OrderStatus = "WORKING" | "FILLED" | "CANCELLED" | "REJECTED";
export interface Order { id: number; symbol: string; side: TradeSide; quantity: number; type: OrderType; created: number; status: OrderStatus; fillPrice?: number; updated: number; note?: string; triggered?: boolean }
export interface Fill { id: number; orderID: number; symbol: string; side: TradeSide; quantity: number; price: number; time: number; realized: number }
export interface Position { symbol: string; quantity: number; averageCost: number; realized: number }
/** Top of book: buys lift the ask, sells hit the bid, falling back to last. */
export interface Touch { bid?: number; ask?: number; last: number }

export const r8 = (x: number) => Math.round(x * 1e8) / 1e8;
export const limitOf = (t: OrderType) => (t.kind === "limit" || t.kind === "stopLimit" ? t.limit : undefined);
export const stopOf = (t: OrderType) => (t.kind === "stop" || t.kind === "stopLimit" ? t.stop : undefined);
const reserveOf = (t: OrderType) => limitOf(t) ?? stopOf(t);
export const isPendingStop = (o: Order) => stopOf(o.type) != null && o.triggered !== true;
const executable = (t: Touch, side: TradeSide) => (side === "BUY" ? t.ask ?? t.last : t.bid ?? t.last);
export function touchFrom(q?: { bid?: number; ask?: number; last?: number }): Touch | undefined {
  if (!q || q.last == null || !Number.isFinite(q.last) || q.last <= 0) return undefined;
  const ok = (v?: number) => (v != null && Number.isFinite(v) && v > 0 ? r8(v) : undefined);
  return { bid: ok(q.bid), ask: ok(q.ask), last: r8(q.last) };
}
const usd = (v: number) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(v);

export class OrderReject extends Error {}
const isOption = (s: string) => parseOption(s) != null;

/** A margin account with market, limit, stop and stop-limit orders, long and short. Shorts hold 150% of their value. */
export class PaperAccount {
  static startingCash = 1_000_000;
  static shortRequirement = 1.5;
  static maxQuantity = 1e9;
  static maxPrice = 1e12;

  cash = PaperAccount.startingCash;
  positions: Record<string, Position> = {};
  orders: Order[] = [];
  fills: Fill[] = [];
  nextID = 1;
  allowShort = true;

  static from(raw: any): PaperAccount {
    const a = new PaperAccount();
    if (!raw || typeof raw !== "object" || !Number.isFinite(raw.cash)) return a;
    const num = (v: any) => (Number.isFinite(v) ? Number(v) : 0);
    a.cash = num(raw.cash);
    for (const [k, p] of Object.entries<any>(raw.positions ?? {}).slice(0, 2000)) if (typeof k === "string" && k.length <= 64) a.positions[k] = { symbol: k, quantity: num(p.quantity), averageCost: num(p.averageCost), realized: num(p.realized) };
    const side = (s: any): TradeSide => (s === "SELL" ? "SELL" : "BUY");
    const type = (t: any): OrderType => t?.kind === "limit" ? { kind: "limit", limit: num(t.limit) } : t?.kind === "stop" ? { kind: "stop", stop: num(t.stop) } : t?.kind === "stopLimit" ? { kind: "stopLimit", stop: num(t.stop), limit: num(t.limit) } : { kind: "market" };
    const status = (s: any): OrderStatus => (["WORKING", "FILLED", "CANCELLED", "REJECTED"].includes(s) ? s : "CANCELLED");
    a.orders = (Array.isArray(raw.orders) ? raw.orders : []).slice(-5000).map((o: any) => ({ id: num(o.id), symbol: String(o.symbol).slice(0, 64), side: side(o.side), quantity: num(o.quantity), type: type(o.type),
      created: num(o.created), status: status(o.status), fillPrice: Number.isFinite(o.fillPrice) ? o.fillPrice : undefined, updated: num(o.updated), note: typeof o.note === "string" ? o.note.slice(0, 200) : undefined, triggered: o.triggered === true || undefined }));
    a.fills = (Array.isArray(raw.fills) ? raw.fills : []).slice(-5000).map((f: any) => ({ id: num(f.id), orderID: num(f.orderID), symbol: String(f.symbol).slice(0, 64), side: side(f.side), quantity: num(f.quantity), price: num(f.price), time: num(f.time), realized: num(f.realized) }));
    a.nextID = Math.max(num(raw.nextID), ...a.orders.map((o) => o.id + 1), 1);
    a.allowShort = raw.allowShort !== false;
    return a;
  }

  get workingOrders() { return this.orders.filter((o) => o.status === "WORKING"); }
  /** Cash committed to working buys, so they can't be double-spent. */
  get reservedCash() { return r8(this.workingOrders.filter((o) => o.side === "BUY").reduce((s, o) => s + o.quantity * (reserveOf(o.type) ?? 0), 0)); }
  /** Margin held against open shorts, valued at their average sale price. */
  get shortMarginHeld() { return r8(Object.values(this.positions).filter((p) => p.quantity < 0).reduce((s, p) => s + -p.quantity * p.averageCost * PaperAccount.shortRequirement, 0)); }
  get buyingPower() { return r8(this.cash - this.reservedCash - this.shortMarginHeld); }
  private reservedQuantity(symbol: string) { return this.workingOrders.filter((o) => o.symbol === symbol && o.side === "SELL").reduce((s, o) => s + o.quantity, 0); }

  /** Validates and enters an order. Marketable orders fill immediately at the touch. */
  submit(symbol: string, side: TradeSide, quantity: number, type: OrderType, touch?: Touch, now = Date.now()): Order {
    quantity = r8(quantity);
    if (!(quantity > 0) || quantity > PaperAccount.maxQuantity) throw new OrderReject("Quantity must be positive");
    for (const p of [limitOf(type), stopOf(type)]) if (p != null && (!Number.isFinite(p) || p > PaperAccount.maxPrice)) throw new OrderReject("Limit price must be positive");
    const lp = limitOf(type), sp = stopOf(type);
    if (lp != null && lp <= 0) throw new OrderReject("Limit price must be positive");
    if (sp != null) {
      if (sp <= 0) throw new OrderReject("Stop price must be positive");
      // A stop already through the market would fill at once: almost always a typo.
      if (touch && (side === "BUY" ? sp <= touch.last : sp >= touch.last)) throw new OrderReject(side === "BUY" ? "Buy stop must be above the last price" : "Sell stop must be below the last price");
    }
    if (type.kind === "market" && !touch) throw new OrderReject("No market data for this security yet");
    const px = reserveOf(type) ?? executable(touch!, side);
    const held = this.positions[symbol]?.quantity ?? 0;
    if (side === "BUY") {
      // Covering a short releases its margin, so only the part that opens or extends a long needs cash.
      const covering = Math.min(quantity, Math.max(-held, 0));
      const released = covering * (this.positions[symbol]?.averageCost ?? 0) * PaperAccount.shortRequirement;
      const estimate = r8(quantity * px), avail = r8(this.buyingPower + released);
      if (estimate > avail) throw new OrderReject(`Insufficient cash: need ${usd(estimate)}, have ${usd(avail)}`);
    } else {
      const free = Math.max(held, 0) - this.reservedQuantity(symbol);
      const shortPart = quantity - Math.max(free, 0);
      if (shortPart > 0) {
        if (!this.allowShort || isOption(symbol)) throw new OrderReject(`Shorting is off for this ${isOption(symbol) ? "option (long premium only)" : "account"}: you hold ${Math.max(free, 0)}`);
        const needed = r8(shortPart * px * (PaperAccount.shortRequirement - 1)); // proceeds cover the other 100%
        if (needed > this.buyingPower) throw new OrderReject(`Insufficient margin to short: need ${usd(needed)}, have ${usd(this.buyingPower)}`);
      }
    }
    const order: Order = { id: this.nextID++, symbol, side, quantity, type, created: now, status: "WORKING", updated: now };
    this.orders.push(order);
    if (touch) this.mark(symbol, touch, now);
    return this.orders.find((o) => o.id === order.id)!;
  }

  cancel(id: number, now = Date.now()) {
    const o = this.orders.find((x) => x.id === id && x.status === "WORKING");
    if (o) { o.status = "CANCELLED"; o.updated = now; }
  }

  /** Feeds a new touch for `symbol`; fills every working order it crosses. Returns new fills. */
  mark(symbol: string, touch: Touch, now = Date.now()): Fill[] {
    const out: Fill[] = [];
    for (const o of this.orders) {
      if (o.symbol !== symbol || o.status !== "WORKING") continue;
      const sp = stopOf(o.type);
      if (isPendingStop(o) && sp != null) {
        // Stops trigger on the last trade, not the quote, like exchange stop orders.
        if (!(o.side === "BUY" ? touch.last >= sp : touch.last <= sp)) continue;
        o.triggered = true; o.updated = now; o.note = `Triggered at ${touch.last}`;
      }
      const px = executable(touch, o.side), lim = limitOf(o.type);
      if (lim != null && (o.side === "BUY" ? px > lim : px < lim)) continue; // price improvement goes to the trader
      const f = this.execute(o, px, now);
      if (f) out.push(f);
    }
    return out;
  }

  private execute(o: Order, price: number, now: number): Fill | undefined {
    const notional = r8(o.quantity * price);
    let realized = 0;
    const pos: Position = { ...(this.positions[o.symbol] ?? { symbol: o.symbol, quantity: 0, averageCost: 0, realized: 0 }) };
    const reject = (note: string) => { o.status = "REJECTED"; o.note = note; o.updated = now; return undefined; };
    if (o.side === "BUY") {
      const covering = Math.min(o.quantity, Math.max(-pos.quantity, 0));
      const available = this.cash - (this.reservedCash - o.quantity * (reserveOf(o.type) ?? 0)) - this.shortMarginHeld + covering * pos.averageCost * PaperAccount.shortRequirement;
      if (notional > r8(available)) return reject("Insufficient cash at fill");
      if (covering > 0) { realized = (pos.averageCost - price) * covering; pos.quantity = r8(pos.quantity + covering); }
      const opening = r8(o.quantity - covering);
      if (opening > 0) { const q = r8(pos.quantity + opening); pos.averageCost = r8((pos.averageCost * pos.quantity + opening * price) / q); pos.quantity = q; }
      this.cash = r8(this.cash - notional);
    } else {
      const closing = Math.min(o.quantity, Math.max(pos.quantity, 0)), opening = r8(o.quantity - closing);
      if (opening > 0 && (!this.allowShort || isOption(o.symbol))) return reject("Position no longer available");
      if (closing > 0) { realized = (price - pos.averageCost) * closing; pos.quantity = r8(pos.quantity - closing); }
      if (opening > 0) { const sq = r8(-pos.quantity + opening); pos.averageCost = r8((-pos.quantity * pos.averageCost + opening * price) / sq); pos.quantity = -sq; }
      this.cash = r8(this.cash + notional);
    }
    realized = r8(realized);
    pos.realized = r8(pos.realized + realized);
    if (pos.quantity === 0) pos.averageCost = 0;
    this.positions[o.symbol] = pos;
    o.status = "FILLED"; o.fillPrice = price; o.updated = now;
    const fill: Fill = { id: this.fills.length + 1, orderID: o.id, symbol: o.symbol, side: o.side, quantity: o.quantity, price, time: now, realized };
    this.fills.push(fill);
    return fill;
  }

  get openPositions() { return Object.values(this.positions).filter((p) => p.quantity !== 0).sort((a, b) => a.symbol.localeCompare(b.symbol)); }
  get realizedPnL() { return r8(Object.values(this.positions).reduce((s, p) => s + p.realized, 0)); }
  /** Account value with positions marked at `marks` (cost when unmarked). */
  equity(marks: Record<string, number>) { return r8(this.cash + this.openPositions.reduce((s, p) => s + p.quantity * (marks[p.symbol] ?? p.averageCost), 0)); }
}
