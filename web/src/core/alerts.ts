/** Price alerts, ported from KestrelCore's AlertBook. Each alert fires once, on the first quote that meets it. */
export type AlertCondition = { kind: "above"; level: number } | { kind: "below"; level: number } | { kind: "move"; percent: number };
export interface PriceAlert { id: string; symbol: string; condition: AlertCondition; created: number; triggered?: number; triggerPrice?: number }

const sig = (v: number) => new Intl.NumberFormat("en-US", { maximumSignificantDigits: 10 }).format(v);
export const conditionLabel = (c: AlertCondition) => (c.kind === "above" ? `LAST ≥ ${sig(c.level)}` : c.kind === "below" ? `LAST ≤ ${sig(c.level)}` : `|CHG| ≥ ${+c.percent.toFixed(2)}%`);

export class AlertError extends Error {}

export class AlertBook {
  static maxActive = 200;
  static maxHistory = 200;
  alerts: PriceAlert[] = [];

  static from(raw: any): AlertBook {
    const b = new AlertBook();
    const cond = (c: any): AlertCondition | null => c?.kind === "above" && Number.isFinite(c.level) ? { kind: "above", level: c.level } : c?.kind === "below" && Number.isFinite(c.level) ? { kind: "below", level: c.level } : c?.kind === "move" && Number.isFinite(c.percent) ? { kind: "move", percent: c.percent } : null;
    b.alerts = (Array.isArray(raw?.alerts) ? raw.alerts : []).slice(0, AlertBook.maxActive + AlertBook.maxHistory).flatMap((a: any) => {
      const c = cond(a?.condition);
      return c && typeof a.symbol === "string" && a.symbol.length <= 64 ? [{ id: String(a.id).slice(0, 40), symbol: a.symbol, condition: c, created: Number(a.created) || 0,
        triggered: Number.isFinite(a.triggered) ? a.triggered : undefined, triggerPrice: Number.isFinite(a.triggerPrice) ? a.triggerPrice : undefined }] : [];
    });
    return b;
  }

  get active() { return this.alerts.filter((a) => a.triggered == null); }
  get history() { return this.alerts.filter((a) => a.triggered != null).sort((a, b) => b.triggered! - a.triggered!); }
  get watchedSymbols() { return new Set(this.active.map((a) => a.symbol)); }

  /** Level alerts must be on the far side of the current price, so a new alert never fires instantly by accident. */
  add(symbol: string, condition: AlertCondition, last: number | undefined, now = Date.now(), id: string = globalThis.crypto.randomUUID()): PriceAlert {
    if (this.active.length >= AlertBook.maxActive) throw new AlertError("Alert limit reached: cancel some first");
    const v = condition.kind === "move" ? condition.percent : condition.level;
    if (!Number.isFinite(v) || v <= 0 || (condition.kind === "move" && v > 100)) throw new AlertError("Enter a positive level (move % must be between 0 and 100)");
    if (last != null && ((condition.kind === "above" && last >= condition.level) || (condition.kind === "below" && last <= condition.level))) throw new AlertError(`Price is already through that level (last ${last})`);
    const a: PriceAlert = { id, symbol, condition, created: now };
    this.alerts.push(a);
    return a;
  }
  cancel(id: string) { this.alerts = this.alerts.filter((a) => !(a.id === id && a.triggered == null)); }
  clearHistory() { this.alerts = this.alerts.filter((a) => a.triggered == null); }

  /** Checks a fresh quote against every active alert on `symbol`; returns the ones that fired. */
  evaluate(symbol: string, last: number, changePercent: number | undefined, now = Date.now()): PriceAlert[] {
    const fired: PriceAlert[] = [];
    for (const a of this.alerts) {
      if (a.symbol !== symbol || a.triggered != null) continue;
      const c = a.condition;
      const hit = c.kind === "above" ? last >= c.level : c.kind === "below" ? last <= c.level : changePercent != null && Math.abs(changePercent) >= c.percent;
      if (hit) { a.triggered = now; a.triggerPrice = last; fired.push(a); }
    }
    if (fired.length) { const old = new Set(this.history.slice(AlertBook.maxHistory).map((a) => a.id)); this.alerts = this.alerts.filter((a) => !old.has(a.id)); }
    return fired;
  }
}
