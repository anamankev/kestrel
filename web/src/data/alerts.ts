import { Store } from "./store";
import { market } from "./market";
import { AlertBook, conditionLabel, type AlertCondition, type PriceAlert } from "../core/alerts";
import { changePercent } from "../core/market";
import { instrument } from "../core/universe";
import type { Instrument } from "../core/instrument";

/** The signed-in user's alerts: checked on every quote, saved in the encrypted vault, shown as a toast and (if allowed) a browser notification. */
export class AlertService extends Store {
  book = new AlertBook();
  lastAlert: PriceAlert | null = null;
  persist: () => void = () => {};
  private started = false;
  private seen = new Map<string, number>();

  snapshot() { return { alerts: this.book.alerts }; }
  restore(raw: any) { this.book = AlertBook.from(raw); this.lastAlert = null; this.emit(); }

  start() {
    if (this.started) return;
    this.started = true;
    market.subscribe(() => this.check());
    market.held.push(() => this.book.watchedSymbols);
  }

  add(i: Instrument, c: AlertCondition) {
    this.book.add(i.symbol, c, market.quotes.get(i.symbol)?.last);
    // Asked here, on a click, so the browser shows its permission prompt.
    if (typeof Notification !== "undefined" && Notification.permission === "default") void Notification.requestPermission().catch(() => {});
    this.persist(); this.emit();
  }
  cancel(id: string) { this.book.cancel(id); this.persist(); this.emit(); }
  clearHistory() { this.book.clearHistory(); this.persist(); this.emit(); }

  private check() {
    let fired: PriceAlert[] = [];
    for (const s of this.book.watchedSymbols) {
      const q = market.quotes.get(s);
      if (!q || this.seen.get(s) === q.time + q.last) continue;
      this.seen.set(s, q.time + q.last);
      fired = fired.concat(this.book.evaluate(s, q.last, changePercent(q)));
    }
    if (!fired.length) return;
    this.lastAlert = fired[fired.length - 1];
    for (const a of fired) this.notify(a);
    this.persist(); this.emit();
  }

  private notify(a: PriceAlert) {
    if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
    const t = instrument(a.symbol)?.ticker ?? a.symbol;
    try { new Notification(`${t} alert`, { body: `${conditionLabel(a.condition)} · last ${a.triggerPrice}`, tag: a.id }); } catch { /* some browsers only allow notifications from a service worker */ }
  }
}

export const alerts = new AlertService();
